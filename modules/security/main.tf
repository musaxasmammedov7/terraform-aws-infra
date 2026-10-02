# =====================================================================
# Security layer
# AWS Config (recording), Security Hub (FSBP + CIS standards),
# IAM account password policy (CIS 1.1), S3 server-access-log target,
# and the Security Hub -> EventBridge -> SNS notification path.
#
# Depends on: data (KMS key to encrypt the Config bucket).
# NOTE: CloudTrail/AWS Backup already exist in edge; here we add
# scanning + notifications. Raw resources - no community module exists.
# =====================================================================

locals {
  name = "${var.project}-${var.environment}"
}

data "aws_partition" "current" {}

# ---------------------------------------------------------------------
# AWS Config
#   recorder      - continuously records ALL resource types (+ global)
#   delivery      - snapshots/history -> encrypted S3 bucket
#   status        - actually starts recording
# ---------------------------------------------------------------------

module "config_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.16.1"

  bucket = "${var.project}-${var.environment}-config"

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = var.kms_key_arn
      }
      bucket_key_enabled = true
    }
  }

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  # AWS Config must be allowed to write snapshots/history
  attach_policy = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigAclCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = "arn:aws:s3:::${var.project}-${var.environment}-config"
      },
      {
        Sid       = "AWSConfigWrite"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${var.project}-${var.environment}-config/config/*"
      }
    ]
  })

  lifecycle_rule = [
    {
      id      = "expire-config-snapshots"
      enabled = true
      expiration = {
        days = 90
      }
    }
  ]

  tags = var.tags
}

module "config_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name            = "${local.name}-config"
  description     = "IAM role for AWS Config"
  use_name_prefix = true

  trust_policy_permissions = {
    Config = {
      actions = ["sts:AssumeRole"]
      principals = [{
        type        = "Service"
        identifiers = ["config.amazonaws.com"]
      }]
    }
  }

  policies = {
    AWSConfigRole = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
  }

  tags = var.tags
}

resource "aws_config_configuration_recorder" "this" {
  name     = "${local.name}-config-recorder"
  role_arn = module.config_role.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "${local.name}-config-delivery"
  s3_bucket_name = module.config_bucket.s3_bucket_id
  s3_key_prefix  = "config"

  snapshot_delivery_properties {
    delivery_frequency = "Twelve_Hours"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

# ---------------------------------------------------------------------
# Security Hub + standards
# ---------------------------------------------------------------------
resource "aws_securityhub_account" "this" {
  count = var.enable_security_hub ? 1 : 0

  # Don't auto-enable the default standards - we subscribe explicitly below
  enable_default_standards = false
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  count         = var.enable_security_hub ? 1 : 0
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

resource "aws_securityhub_standards_subscription" "cis" {
  count         = var.enable_security_hub ? 1 : 0
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
  depends_on    = [aws_securityhub_account.this]
}

# ---------------------------------------------------------------------
# CIS 1.1 - IAM account password policy
# ---------------------------------------------------------------------
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}

# ---------------------------------------------------------------------
# Notifications: Security Hub -> EventBridge -> SNS -> email
# (Babenko modules: sns + eventbridge)
# ---------------------------------------------------------------------
module "sns_security_alerts" {
  source  = "terraform-aws-modules/sns/aws"
  version = "7.1.1"

  name = "${local.name}-security-alerts"

  create_topic_policy = true
  topic_policy_statements = {
    EventBridge = {
      effect  = "Allow"
      actions = ["sns:Publish"]
      principals = [{
        type        = "Service"
        identifiers = ["events.amazonaws.com"]
      }]
    }
  }

  subscriptions = {
    email = {
      protocol = "email"
      endpoint = var.email
    }
  }

  tags = var.tags
}

module "eventbridge_securityhub" {
  source  = "terraform-aws-modules/eventbridge/aws"
  version = "4.3.2"

  # Use the default event bus (Security Hub publishes there)
  create_bus = false

  rules = {
    securityhub-findings = {
      description = "Forward Security Hub CRITICAL/HIGH findings to SNS"
      event_pattern = jsonencode({
        source      = ["aws.securityhub"]
        detail-type = ["Security Hub Findings - Imported"]
        detail = {
          findings = {
            Severity = {
              Label = ["CRITICAL", "HIGH"]
            }
          }
        }
      })
    }
  }

  targets = {
    securityhub-findings = [
      {
        name = "security-alerts"
        arn  = module.sns_security_alerts.topic_arn
      }
    ]
  }

  tags = var.tags
}