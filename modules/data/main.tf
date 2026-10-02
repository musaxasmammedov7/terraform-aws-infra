# =====================================================================
# Data layer
# KMS, RDS PostgreSQL (Multi-AZ, private), private S3, SQS + DLQ,
# Secrets Manager and SSM Parameter Store.
# Depends on: network (subnet group + DB SG) and iam (queue policy roles).
# =====================================================================

#             AWS Infrastructure
#                           │
#        ┌──────────────────┼──────────────────┐
#        │                  │                  │
#       KMS                RDS                S3
#        │                  │                  │
#   шифрование          PostgreSQL          файлы
#        │
#        ├────────────── SQS ──────────────┐
#        │              очередь            │
#        │                                  │
#        ├──────── Secrets Manager          │
#        │              секреты             │
#        │                                  │
#        └──────── SSM Parameter Store(здесь находится конфигурация или юрл эндпоинтов чтобы не надо было прописовать user-data)     │
#                      конфигурация  

locals {
  name    = "${var.project}-${var.environment}"
  account = data.aws_caller_identity.current.account_id
  region  = var.region

  jobs_queue_arn = "arn:aws:sqs:${var.region}:${local.account}:${var.project}-${var.environment}-jobs"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------
# KMS: one master key encrypts everything (RDS, S3, SQS, Secrets, EBS,
# CloudTrail, Backup). The key policy explicitly grants each AWS service.
# ---------------------------------------------------------------------

#дает разрешение использовагнием мастером ключом шифрования бэк и воркер инстансу и также создает key_statemnts в котором указывает каким сервисам дать доступ

module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "4.2.2"

  description             = "${local.name} master encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  aliases = ["${local.name}/main"]

  key_users = [
    var.backend_role_arn,
    var.workers_role_arn,
  ]

  key_statements = [
    {
      sid        = "AllowRDS"
      effect     = "Allow"
      actions    = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:ReEncryptFrom", "kms:ReEncryptTo", "kms:CreateGrant", "kms:RetireGrant"]
      resources  = ["*"]
      principals = [{ type = "Service", identifiers = ["rds.amazonaws.com"] }]
      condition  = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account] }]
    },
    {
      sid        = "AllowSQS"
      effect     = "Allow"
      actions    = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext", "kms:DescribeKey", "kms:CreateGrant"]
      resources  = ["*"]
      principals = [{ type = "Service", identifiers = ["sqs.amazonaws.com"] }]
      condition  = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account] }]
    },
    {
      sid        = "AllowSecretsManager"
      effect     = "Allow"
      actions    = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:ReEncryptFrom", "kms:ReEncryptTo", "kms:CreateGrant"]
      resources  = ["*"]
      principals = [{ type = "Service", identifiers = ["secretsmanager.amazonaws.com"] }]
      condition  = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account] }]
    },
    {
      sid        = "AllowCloudWatchLogs"
      effect     = "Allow"
      actions    = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
      resources  = ["*"]
      principals = [{ type = "Service", identifiers = ["logs.amazonaws.com"] }]
      condition  = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account] }]
    },
    {
      sid        = "AllowCloudTrail"
      effect     = "Allow"
      actions    = ["kms:GenerateDataKey", "kms:Decrypt", "kms:DescribeKey", "kms:ReEncryptFrom", "kms:ReEncryptTo", "kms:Encrypt"]
      resources  = ["*"]
      principals = [{ type = "Service", identifiers = ["cloudtrail.amazonaws.com"] }]
    },
    {
      sid        = "AllowEBS"
      effect     = "Allow"
      actions    = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:CreateGrant"]
      resources  = ["*"]
      principals = [{ type = "Service", identifiers = ["ec2.amazonaws.com"] }]
      condition  = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account] }]
    },
    {
      sid        = "AllowELB"
      effect     = "Allow"
      actions    = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:CreateGrant"]
      resources  = ["*"]
      principals = [{ type = "Service", identifiers = ["elasticloadbalancing.amazonaws.com"] }]
      condition  = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account] }]
    },
    {
      sid        = "AllowBackup"
      effect     = "Allow"
      actions    = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
      resources  = ["*"]
      principals = [{ type = "Service", identifiers = ["backup.amazonaws.com"] }]
      condition  = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account] }]
    },
  ]

  tags = var.tags
}

# ---------------------------------------------------------------------
# RDS PostgreSQL, Multi-AZ, in the private database subnets (local-only RT)
# ---------------------------------------------------------------------

#создание бд также пароль автоматом создается и отпарвялется в secret manager

module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.2.2"

  identifier = "${local.name}-postgres"

  engine                 = "postgres"
  engine_version         = "16.4"
  family                 = "postgres16"
  major_engine_version   = "16"
  create_db_option_group = false

  instance_class        = var.db_instance_class
  allocated_storage     = 20
  storage_type          = "gp3"
  max_allocated_storage = 100
  storage_encrypted     = true
  kms_key_id            = module.kms.key_arn

  db_name  = var.db_name
  username = var.db_username
  port     = var.db_port

  # Password generated + rotated by RDS, stored in Secrets Manager
  manage_master_user_password = true

  # Network: private data subnets + dedicated DB security group
  create_db_subnet_group = false
  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [var.db_sg_id]

  multi_az = var.multi_az

  backup_retention_period = var.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  apply_immediately       = false

  deletion_protection              = true
  skip_final_snapshot              = false
  final_snapshot_identifier_prefix = "final"

  # Observability
  monitoring_interval                   = 60
  create_monitoring_role                = true
  monitoring_role_name                  = "${local.name}-rds-monitoring"
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = module.kms.key_arn
  enabled_cloudwatch_logs_exports       = ["postgresql"]
  create_cloudwatch_log_group           = true

  tags = merge(var.tags, { Backup = "true" })
}

# ---------------------------------------------------------------------
# S3 bucket for user files - PRIVATE, no public access.
# Access only via IAM roles and presigned URLs issued by the backend.
# ---------------------------------------------------------------------

#

module "files_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.16.1"

  bucket = "${var.project}-${var.environment}-files"

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
        kms_master_key_id = module.kms.key_arn
      }
      bucket_key_enabled = true
    }
  }

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  # FSBP S3.9 - server access logging to the dedicated target bucket
  logging = {
    target_bucket = module.access_logs_bucket.s3_bucket_id
    target_prefix = "files/"
  }

  lifecycle_rule = [
    {
      id      = "expire-noncurrent-versions"
      enabled = true
      noncurrent_version_expiration = {
        days = 30
      }
      abort_incomplete_multipart_upload_days = 7
    }
  ]

  tags = var.tags
}

# ---------------------------------------------------------------------
# S3 bucket for ALB access logs (encrypted, lifecycle-managed)
# ---------------------------------------------------------------------
module "alb_logs_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.16.1"

  bucket = "${var.project}-${var.environment}-alb-logs"

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = module.kms.key_arn
      }
      bucket_key_enabled = true
    }
  }

  # Allow the ALB/NLB service to write access logs
  attach_lb_log_delivery_policy = true

  # FSBP S3.9 - server access logging to the dedicated target bucket
  logging = {
    target_bucket = module.access_logs_bucket.s3_bucket_id
    target_prefix = "alb-logs/"
  }

  lifecycle_rule = [
    {
      id      = "expire-logs"
      enabled = true
      expiration = {
        days = 30
      }
    }
  ]

  tags = var.tags
}

# ---------------------------------------------------------------------
# S3 bucket - target for server access logging (FSBP S3.9).
# Source buckets write their access logs here; this bucket itself does
# not log (that would recurse). Source ARNs are built by convention to
# avoid a Terraform dependency cycle (bucket <-> log target).
# ---------------------------------------------------------------------
module "access_logs_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.16.1"

  bucket = "${var.project}-${var.environment}-access-logs"

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = module.kms.key_arn
      }
      bucket_key_enabled = true
    }
  }

  # Allow the source buckets to deliver server access logs here
  attach_access_log_delivery_policy = true
  access_log_delivery_policy_source_buckets = [
    "arn:aws:s3:::${var.project}-${var.environment}-files",
    "arn:aws:s3:::${var.project}-${var.environment}-alb-logs",
    "arn:aws:s3:::${var.project}-${var.environment}-cloudtrail",
  ]

  lifecycle_rule = [
    {
      id      = "expire-access-logs"
      enabled = true
      expiration = {
        days = 30
      }
    }
  ]

  tags = var.tags
}

# ---------------------------------------------------------------------
# SQS queue for background jobs + DLQ
# Backend publishes (SendMessage), workers consume (Receive/Delete).
# ---------------------------------------------------------------------
module "jobs_queue" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "5.2.2"

  name = "${var.project}-${var.environment}-jobs"

  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600 # 14 days
  delay_seconds              = 0

  kms_master_key_id = module.kms.key_arn

  # Dead-letter queue
  create_dlq = true
  redrive_policy = {
    maxReceiveCount = 5
  }

  # Queue policy: only backend can send, only workers can consume
  create_queue_policy = true
  queue_policy_statements = {
    backend-send = {
      effect     = "Allow"
      actions    = ["sqs:SendMessage"]
      principals = [{ type = "AWS", identifiers = [var.backend_role_arn] }]
      resources  = [local.jobs_queue_arn]
    }
    workers-consume = {
      effect     = "Allow"
      actions    = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
      principals = [{ type = "AWS", identifiers = [var.workers_role_arn] }]
      resources  = [local.jobs_queue_arn]
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------
# Secrets Manager: application secret (e.g. JWT signing key)
# Random value generated at apply time and stored write-only (not in state).
# ---------------------------------------------------------------------
module "app_secret" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "2.2.0"

  name                   = "${local.name}-app"
  description            = "Application secrets for ${local.name}"
  create_random_password = true
  secret_string_wo = jsonencode({
    jwt_secret = "generated-at-apply-time"
  })

  kms_key_id = module.kms.key_arn

  recovery_window_in_days = 7

  tags = var.tags
}

# ---------------------------------------------------------------------
# SSM Parameter Store: non-sensitive configuration the instances read at
# boot time (via the SSM VPC endpoint) - replaces hardcoding in user_data.
# ---------------------------------------------------------------------
module "ssm_rds_host" {
  source  = "terraform-aws-modules/ssm-parameter/aws"
  version = "2.1.2"

  name  = "/${var.project}/${var.environment}/rds/host"
  value = module.db.db_instance_address
  type  = "String"
}

module "ssm_rds_port" {
  source  = "terraform-aws-modules/ssm-parameter/aws"
  version = "2.1.2"

  name  = "/${var.project}/${var.environment}/rds/port"
  value = tostring(module.db.db_instance_port)
  type  = "String"
}

module "ssm_s3_bucket" {
  source  = "terraform-aws-modules/ssm-parameter/aws"
  version = "2.1.2"

  name  = "/${var.project}/${var.environment}/s3/bucket"
  value = module.files_bucket.s3_bucket_id
  type  = "String"
}

module "ssm_sqs_url" {
  source  = "terraform-aws-modules/ssm-parameter/aws"
  version = "2.1.2"

  name  = "/${var.project}/${var.environment}/sqs/url"
  value = module.jobs_queue.queue_url
  type  = "String"
}

module "ssm_secret_arn" {
  source  = "terraform-aws-modules/ssm-parameter/aws"
  version = "2.1.2"

  name  = "/${var.project}/${var.environment}/secrets/app"
  value = module.app_secret.secret_arn
  type  = "String"
}
