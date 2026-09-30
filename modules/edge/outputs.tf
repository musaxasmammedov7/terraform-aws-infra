output "web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = module.waf.web_acl_arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = module.cloudfront.cloudfront_distribution_domain_name
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = module.cloudfront.cloudfront_distribution_arn
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail trail"
  value       = aws_cloudtrail.this.name
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault"
  value       = aws_backup_vault.this.name
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan"
  value       = aws_backup_plan.this.id
}