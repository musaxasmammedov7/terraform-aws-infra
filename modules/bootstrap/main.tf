# =====================================================================
# Bootstrap layer
# Creates the Terraform state backend for this environment:
#   - S3 bucket for remote state (versioned + encrypted + locked down)
#   - DynamoDB table for state locking
# Apply this layer FIRST, from a machine with AWS credentials.
# =====================================================================

locals {
  name = "${var.project}-${var.environment}"
}

# ---------------------------------------------------------------------
# S3 bucket for Terraform remote state
# ---------------------------------------------------------------------
module "state_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.16.1"

  bucket = "${var.project}-${var.environment}-terraform-state"

  # Lock the bucket down: no public access, owner enforced
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # State files must be recoverable and encrypted
  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "aws:kms"
      }
    }
  }

  # Enforce HTTPS + latest TLS for all access
  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  # Clean up old non-current versions to keep the bucket small
  lifecycle_rule = [
    {
      id      = "expire-noncurrent-versions"
      enabled = true
      noncurrent_version_expiration = {
        days = 30
      }
    }
  ]

  tags = var.tags
}

# ---------------------------------------------------------------------
# DynamoDB table for Terraform state locking
# ---------------------------------------------------------------------
module "lock_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "5.5.2"

  name                           = "${var.project}-${var.environment}-terraform-lock"
  hash_key                       = "LockID"
  billing_mode                   = "PAY_PER_REQUEST"
  server_side_encryption_enabled = true
  point_in_time_recovery_enabled = true

  attributes = [
    { name = "LockID", type = "S" }
  ]

  tags = var.tags
}