# Terraform infrastructure (Terragrunt + terraform-aws-modules)

Multi-environment AWS infrastructure (**test** and **prod**) for the following
architecture, implemented with the official
[terraform-aws-modules](https://github.com/terraform-aws-modules) (Anton Babenko)
modules and wrapped with [Terragrunt](https://terragrunt.gruntwork.io/).

```
Route53 -> CloudFront (WAF, Shield Standard, caching)
        -> Internet Gateway -> internet-facing ALB (ACM TLS, health checks)
        -> 2 public subnets (one NAT Gateway per AZ)
        -> 3 Auto Scaling Groups (Frontend, Backend API, Workers) in private subnets
        -> RDS PostgreSQL (Multi-AZ, private) + S3 (private, presigned URLs)
        -> SQS (backend publishes, workers consume)
Management: SSM (no SSH), Secrets Manager, KMS, CloudTrail, CloudWatch, AWS Backup
```

## Repository layout

```
infra/
├── root.hcl                    # root: AWS provider generation, globals
├── envs/
│   ├── test/  env.hcl            # test values (region us-east-1)
│   │   ├── 00-bootstrap/         # S3 state bucket + DynamoDB lock
│   │   ├── 10-network/           # VPC, subnets, NAT, endpoints, SGs, DNS zone
│   │   ├── 30-iam/               # EC2 roles + instance profiles (SSM-first)
│   │   ├── 20-data/              # KMS, RDS, S3, SQS, Secrets, SSM
│   │   ├── 40-compute/           # ACM, ALB, 3x ASG, CloudWatch alarms
│   │   ├── 50-edge/              # WAF, CloudFront, Route53, CloudTrail, Backup
│   │   └── 60-security/          # AWS Config, Security Hub, SNS alerts
│   └── prod/   env.hcl           # same layers, production values
└── modules/                      # thin root modules wrapping community modules
    ├── bootstrap/ network/ iam/ data/ compute/ edge/ security/
```

Each layer is an independent Terragrunt unit with its own remote state in
`myapp-<env>-terraform-state` (S3) locked by `myapp-<env>-terraform-lock`
(DynamoDB).

## Prerequisites

- Terraform >= 1.5
- Terragrunt >= 1.1
- AWS credentials (profile / SSO / env vars), region `us-east-1`

## How to deploy

Apply order is fixed by Terragrunt dependencies, but **bootstrap must be
applied first** because the state bucket must exist before the other layers
can `init`.

```bash
# 1. State backend (from a machine with AWS credentials)
cd envs/test/00-bootstrap
terragrunt init && terragrunt apply

# 2. Everything else, respecting dependencies
cd ../..
terragrunt run-all init
terragrunt run-all apply
```

To validate without applying:

```bash
terragrunt run-all plan
terragrunt run-all validate
```

## Modules used (all from `terraform-aws-modules`, pinned versions)

| Layer | Module (registry) | Version |
|---|---|---|
| bootstrap | `terraform-aws-modules/s3-bucket/aws`, `.../dynamodb-table/aws` | 5.16.1, 5.5.2 |
| network   | `terraform-aws-modules/vpc/aws` (+ `//modules/vpc-endpoints`) | 6.7.3 |
| network   | `terraform-aws-modules/security-group/aws` | 6.0.0 |
| network   | `terraform-aws-modules/route53/aws` | 6.5.1 |
| iam       | `terraform-aws-modules/iam/aws//modules/iam-role` | 6.8.2 |
| data      | `terraform-aws-modules/kms/aws`, `.../rds/aws`, `.../s3-bucket/aws` | 4.2.2, 7.2.2, 5.16.1 |
| data      | `terraform-aws-modules/sqs/aws`, `.../secrets-manager/aws`, `.../ssm-parameter/aws` | 5.2.2, 2.2.0, 2.1.2 |
| compute   | `terraform-aws-modules/acm/aws`, `.../alb/aws`, `.../autoscaling/aws` | 6.3.1, 10.5.1, 9.3.2 |
| compute   | `terraform-aws-modules/cloudwatch/aws//modules/metric-alarm` | 5.7.3 |
| edge      | `terraform-aws-modules/wafv2/aws`, `.../cloudfront/aws`, `.../route53/aws` | 2.1.0, 6.7.1, 6.5.1 |
| security | `terraform-aws-modules/s3-bucket/aws` (Config bucket), `.../iam/aws//modules/iam-role` (Config role) | 5.16.1, 6.8.2 |
| security | `terraform-aws-modules/sns/aws`, `.../eventbridge/aws` (notifications) | 7.1.1, 4.3.2 |

Three components have **no** community module from `terraform-aws-modules`
(AWS Config, Security Hub, and CloudTrail/AWS Backup) and use raw AWS
resources - inside the `security` (Config, Security Hub) and `edge`
(CloudTrail, Backup) layers. SNS + EventBridge alerts are built from the
Babenko modules. Shield Standard is enabled automatically for CloudFront and
needs no configuration.

## Security highlights

- Instances are in private subnets, **no public IPs**, **no SSH** - SSM only.
- **IMDSv2 required**, EBS volumes encrypted with a dedicated KMS key.
- Security-group tiering: CloudFront -> ALB -> App -> DB (5432 only from App+Workers).
- Route tables: Public `0.0.0.0/0 -> IGW`; Private `S3 prefix list -> S3 GW endpoint`
  and `0.0.0.0/0 -> NAT`; Data **local only**.
- RDS Multi-AZ, encrypted, deletion protection, managed master password in
  Secrets Manager with automatic rotation, PITR backups.
- S3 bucket fully private - access only via IAM roles and presigned URLs.
- WAF (managed rule groups + rate limiting), HTTPS-only CloudFront, TLS1.2+.
- CloudTrail (multi-region, encrypted, log-file validation) and AWS Backup.
- AWS Config (continuous recording) + Security Hub (FSBP + CIS standards),
  IAM password policy, S3 server access logging, and Security Hub -> EventBridge
  -> SNS email alerts for CRITICAL/HIGH findings.
- Terraform state encrypted, versioned, HTTPS-only, locked with DynamoDB.

## Placeholders to replace before deploying

1. `domain` in `envs/<env>/env.hcl` - point at a domain you control.
2. Resource sizes (`t3.micro`, `db.t3.micro`, etc.) - scale for your workload.
3. `user_data_*.sh.tftpl` in `modules/compute/` - real application start commands.
4. `account_id` is resolved automatically via `get_aws_account_id()`.