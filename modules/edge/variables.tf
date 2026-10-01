variable "project" {
  description = "Project/application name"
  type        = string
}

variable "environment" {
  description = "Environment name (test, prod)"
  type        = string
}

variable "domain" {
  description = "Domain name for the application"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
}

variable "zone_id" {
  description = "Route53 hosted zone ID (from the network layer)"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the master KMS key (from the data layer)"
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of the ALB (from the compute layer)"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate (from the compute layer)"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "access_logs_bucket" {
  description = "Name of the S3 server-access-log target bucket (from the data layer)"
  type        = string
}

variable "backup_retention_days" {
  description = "Number of days to keep AWS Backup recovery points"
  type        = number
  default     = 30
}