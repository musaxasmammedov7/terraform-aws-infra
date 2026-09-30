# =====================================================================
# Edge layer
# WAF, CloudFront, Route53 records, CloudTrail and AWS Backup.
#
# Depends on: network (DNS zone), data (KMS key), compute (ALB DNS, ACM).
#
# NOTE: CloudTrail and AWS Backup have no community module from
# terraform-aws-modules, so they use a small amount of raw resources.
# =====================================================================

locals {
  name    = "${var.project}-${var.environment}"
  account = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------
# WAF v2 (scope CLOUDFRONT -> must be in us-east-1, which is our region)
# AWS managed rule groups + a rate-limit rule.
# Shield Standard is automatically enabled for CloudFront (no config).
# ---------------------------------------------------------------------
module "waf" {
  source  = "terraform-aws-modules/wafv2/aws"
  version = "2.1.0"

  name  = "${local.name}-web-acl"
  scope = "CLOUDFRONT"

  default_action = "allow"

  rules = {
    aws-common = {
      priority        = 10
      override_action = "none"
      statement = {
        managed_rule_group_statement = {
          name        = "AWSManagedRulesCommonRuleSet"
          vendor_name = "AWS"
        }
      }
    }
    aws-ip-reputation = {
      priority        = 20
      override_action = "none"
      statement = {
        managed_rule_group_statement = {
          name        = "AWSManagedRulesAmazonIpReputationList"
          vendor_name = "AWS"
        }
      }
    }
    aws-known-bad-inputs = {
      priority        = 30
      override_action = "none"
      statement = {
        managed_rule_group_statement = {
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
          vendor_name = "AWS"
        }
      }
    }
    aws-sqli = {
      priority        = 40
      override_action = "none"
      statement = {
        managed_rule_group_statement = {
          name        = "AWSManagedRulesSQLiRuleSet"
          vendor_name = "AWS"
        }
      }
    }
    rate-limit = {
      priority = 50
      action   = "block"
      statement = {
        rate_based_statement = {
          limit              = 2000
          aggregate_key_type = "IP"
        }
      }
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------
# CloudFront distribution
# Origin: the ALB (via public internet, TLS). Static content is cached,
# /api/* is forwarded without caching.
# ---------------------------------------------------------------------
module "cloudfront" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "6.7.1"

  comment         = "${local.name} distribution"
  aliases         = [var.domain]
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = "PriceClass_100"

  origin = {
    alb = {
      domain_name = var.alb_dns_name
      custom_origin_config = {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  default_cache_behavior = {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = "658f4d7b-373d-44b6-a92f-f7b5f01fc97e" # Managed-CachingOptimized
    compress               = true
  }

  ordered_cache_behavior = [
    {
      path_pattern           = "/api/*"
      target_origin_id       = "alb"
      viewer_protocol_policy = "redirect-to-https"
      cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39a5" # Managed-CachingDisabled (forwards all)
      allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
      cached_methods         = ["GET", "HEAD"]
    }
  ]

  viewer_certificate = {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # WAF (associated below to avoid the WAF<->CloudFront circular ref)
  web_acl_id = module.waf.web_acl_arn

  tags = var.tags
}

# Associate the Web ACL with the distribution
resource "aws_wafv2_web_acl_association" "cloudfront" {
  resource_arn = module.cloudfront.cloudfront_distribution_arn
  web_acl_arn  = module.waf.web_acl_arn
}

# ---------------------------------------------------------------------
# Route53 records: point the domain (and www) at CloudFront
# ---------------------------------------------------------------------
module "route53_records" {
  source  = "terraform-aws-modules/route53/aws"
  version = "6.5.1"

  create_zone = false
  name        = var.domain

  records = {
    A = {
      name = var.domain
      type = "A"
      alias = {
        name                   = module.cloudfront.cloudfront_distribution_domain_name
        zone_id                = module.cloudfront.cloudfront_distribution_hosted_zone_id
        evaluate_target_health = false
      }
    }
    www = {
      name = "www.${var.domain}"
      type = "A"
      alias = {
        name                   = module.cloudfront.cloudfront_distribution_domain_name
        zone_id                = module.cloudfront.cloudfront_distribution_hosted_zone_id
        evaluate_target_health = false
      }
    }
  }
}

# ---------------------------------------------------------------------
# CloudTrail - audit trail of all API activity in the account.
# Logs go to a dedicated encrypted S3 bucket.
# ---------------------------------------------------------------------
module "cloudtrail_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.16.1"

  bucket = "${var.project}-${var.environment}-cloudtrail"

  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

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

  # CloudTrail must be allowed to write
  attach_policy = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = "arn:aws:s3:::${var.project}-${var.environment}-cloudtrail"
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${var.project}-${var.environment}-cloudtrail/AWSLogs/${local.account}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })

  lifecycle_rule = [
    {
      id      = "expire-logs"
      enabled = true
      expiration = {
        days = 90
      }
    }
  ]

  tags = var.tags
}

resource "aws_cloudtrail" "this" {
  name                          = "${local.name}-trail"
  s3_bucket_name                = module.cloudtrail_bucket.s3_bucket_id
  s3_key_prefix                 = "prefix"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = var.kms_key_arn
  is_organization_trail         = false

  # Management events + data events on the files bucket
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${var.project}-${var.environment}-files/"]
    }
  }

  depends_on = [module.cloudtrail_bucket]
}

# ---------------------------------------------------------------------
# AWS Backup - scheduled backups of RDS (and can be extended to S3/EBS)
# ---------------------------------------------------------------------
module "backup_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name            = "${local.name}-backup"
  description     = "IAM role for AWS Backup"
  use_name_prefix = true

  trust_policy_permissions = {
    Backup = {
      actions = ["sts:AssumeRole"]
      principals = [{
        type        = "Service"
        identifiers = ["backup.amazonaws.com"]
      }]
    }
  }

  policies = {
    AWSBackupServiceRolePolicyForBackup = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  }

  tags = var.tags
}

resource "aws_backup_vault" "this" {
  name        = "${local.name}-backup-vault"
  kms_key_arn = var.kms_key_arn

  tags = var.tags
}

resource "aws_backup_plan" "this" {
  name = "${local.name}-backup-plan"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 1 * * ? *)"
    start_window      = 60
    completion_window = 120

    lifecycle {
      delete_after = var.backup_retention_days
    }

    recovery_point_tags = var.tags
  }

  tags = var.tags
}

resource "aws_backup_selection" "this" {
  name         = "${local.name}-backup-selection"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = module.backup_role.arn

  resources = [
    "arn:aws:rds:*:${local.account}:db:${var.project}-${var.environment}-postgres"
  ]
}