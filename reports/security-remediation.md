# Security Remediation Report

Environment: `test` / `prod` (region `us-east-1`)
Date: ________________
Author: ________________

## 1. Scope

AWS Config enabled (continuous recording of all resource types) and
Security Hub subscribed to:
- AWS Foundational Security Best Practices (FSBP) v1.0.0
- CIS AWS Foundations Benchmark v1.2.0

Notifications: Security Hub -> EventBridge -> SNS (email) for CRITICAL/HIGH.

## 2. Baseline ("before")

Screenshots: `screenshots/before/security-score.png`, `screenshots/before/failed-controls.png`

| Standard | Security score | Failed controls |
|---|---|---|
| FSBP | __% | ___ |
| CIS  | __% | ___ |

### Failed controls (baseline)

| Control | Severity | Resource | Decision |
|---|---|---|---|
| (e.g. S3.9) | MEDIUM | myapp-test-files | fix / suppress / accept |
| ... | | | |

## 3. Fixes applied (in Terraform code - source of truth)

| # | Control | What was fixed | Where in code |
|---|---|---|---|
| 1 | (Config enablement) | AWS Config recorder + delivery channel added | `modules/security/main.tf` |
| 2 | (Security Hub) | Security Hub enabled + FSBP + CIS subscribed | `modules/security/main.tf` |
| 3 | CIS 1.1 | IAM account password policy | `modules/security/main.tf` |
| 4 | FSBP S3.9 | S3 server access logging on files/alb-logs/cloudtrail buckets | `modules/data/main.tf`, `modules/edge/main.tf` |

## 4. After re-run

Screenshots: `screenshots/after/security-score.png`, `screenshots/after/failed-controls.png`

| Standard | Security score | Failed controls |
|---|---|---|
| FSBP | __% | ___ |
| CIS  | __% | ___ |

### Remaining findings

| Control | Severity | Reason left unfixed / justification |
|---|---|---|
| (e.g. CIS 2.x metric filters) | MEDIUM | accepted risk: requires CloudTrail->CloudWatch logs + 12 alarms; out of "critical-only" scope |
| (e.g. MFA root) | HIGH (manual) | accepted risk: requires manual console action / hardware MFA |
| ... | | |

## 5. Accepted risks (documented)

| Risk | Why accepted | Owner |
|---|---|---|
| CIS log-metric-filter alarms not implemented | MEDIUM/LOW, no CI/CD automation yet | |
| Root MFA / console password | manual action, not IaC-manageable | |
| ... | | |

## 6. Notification path

`Security Hub finding (CRITICAL/HIGH) -> EventBridge rule -> SNS topic
(myapp-<env>-security-alerts) -> email`.