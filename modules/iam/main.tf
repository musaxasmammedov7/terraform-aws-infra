# =====================================================================
# IAM layer
# IAM roles + instance profiles for the three Auto Scaling Groups.
# Least-privilege: each role can only do what its tier needs.
# SSM access (AmazonSSMManagedInstanceCore) replaces SSH everywhere.
#
# This layer is independent from data/network (resource ARNs are built
# from naming conventions), so the data layer can reference these roles.
# =====================================================================

#Здесь созданы роли для инстансов                     
#                     │
#        ┌────────────┼────────────┐
#       │            │            │
#     Backend      Workers      Frontend
#        │            │            │
#        ▼            ▼            ▼
#      IAM Role     IAM Role     IAM Role
#        │            │            │
#   ┌────┼────┐    ┌──┼───┐       │
#   │    │    │    │  │   │       │
#  S3   SQS  KMS  SQS S3 KMS      S3
#   │         │       │     │       │
#   └────┐    │       └──┐  │       │
#        ▼    ▼          ▼  ▼       ▼
#      Secrets Manager

locals {
  name    = "${var.project}-${var.environment}"
  account = data.aws_caller_identity.current.account_id
  region  = var.region

  files_bucket = "${var.project}-${var.environment}-files"
  jobs_queue   = "${var.project}-${var.environment}-jobs"
  kms_alias    = "arn:aws:kms:${local.region}:${local.account}:alias/${local.name}/main"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------
# Backend role: S3 (presigned URLs), SQS (publish), KMS, Secrets
# ---------------------------------------------------------------------
module "backend_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name                    = "${local.name}-backend"
  description             = "IAM role for backend API instances"
  create_instance_profile = true
  use_name_prefix         = true

  # trust policy: EC2 can assume this role
  trust_policy_permissions = {
    EC2 = {
      actions = ["sts:AssumeRole"]
      principals = [{
        type        = "Service"
        identifiers = ["ec2.amazonaws.com"]
      }]
    }
  }

  # AWS managed policy for SSM (no SSH, admin via Session Manager)
  policies = {
    SSM = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  inline_policy_permissions = {
    s3-files = {
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
      ]
      resources = [
        "arn:aws:s3:::${local.files_bucket}",
        "arn:aws:s3:::${local.files_bucket}/*",
      ]
    }
    sqs-publish = {
      actions = ["sqs:SendMessage"]
      resources = [
        "arn:aws:sqs:${local.region}:${local.account}:${local.jobs_queue}",
      ]
    }
    kms-use = {
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey",
      ]
      resources = [local.kms_alias]
    }
    secrets-read = {
      actions   = ["secretsmanager:GetSecretValue"]
      resources = ["arn:aws:secretsmanager:${local.region}:${local.account}:secret:${local.name}-*"]
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------
# Workers role: SQS (consume), S3 (read), KMS, Secrets
# ---------------------------------------------------------------------
module "workers_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name                    = "${local.name}-workers"
  description             = "IAM role for background worker instances"
  create_instance_profile = true
  use_name_prefix         = true

  trust_policy_permissions = {
    EC2 = {
      actions = ["sts:AssumeRole"]
      principals = [{
        type        = "Service"
        identifiers = ["ec2.amazonaws.com"]
      }]
    }
  }

  policies = {
    SSM = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  inline_policy_permissions = {
    sqs-consume = {
      actions = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueUrl",
        "sqs:GetQueueAttributes",
      ]
      resources = [
        "arn:aws:sqs:${local.region}:${local.account}:${local.jobs_queue}",
      ]
    }
    s3-read = {
      actions = ["s3:GetObject", "s3:ListBucket"]
      resources = [
        "arn:aws:s3:::${local.files_bucket}",
        "arn:aws:s3:::${local.files_bucket}/*",
      ]
    }
    kms-use = {
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey",
      ]
      resources = [local.kms_alias]
    }
    secrets-read = {
      actions   = ["secretsmanager:GetSecretValue"]
      resources = ["arn:aws:secretsmanager:${local.region}:${local.account}:secret:${local.name}-*"]
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------
# Frontend role: minimal (SSM + read-only access to files bucket)
# ---------------------------------------------------------------------
module "frontend_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name                    = "${local.name}-frontend"
  description             = "IAM role for frontend instances"
  create_instance_profile = true
  use_name_prefix         = true

  trust_policy_permissions = {
    EC2 = {
      actions = ["sts:AssumeRole"]
      principals = [{
        type        = "Service"
        identifiers = ["ec2.amazonaws.com"]
      }]
    }
  }

  policies = {
    SSM = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  inline_policy_permissions = {
    s3-read = {
      actions = ["s3:GetObject", "s3:ListBucket"]
      resources = [
        "arn:aws:s3:::${local.files_bucket}",
        "arn:aws:s3:::${local.files_bucket}/*",
      ]
    }
  }

  tags = var.tags
}
