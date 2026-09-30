output "kms_key_arn" {
  description = "ARN of the master KMS key"
  value       = module.kms.key_arn
}

output "kms_key_id" {
  description = "ID of the master KMS key"
  value       = module.kms.key_id
}

output "db_host" {
  description = "RDS PostgreSQL endpoint (private DNS name)"
  value       = module.db.db_instance_address
}

output "db_port" {
  description = "RDS PostgreSQL port"
  value       = module.db.db_instance_port
}

output "db_master_secret_arn" {
  description = "ARN of the RDS master user secret in Secrets Manager"
  value       = module.db.db_instance_master_user_secret_arn
}

output "files_bucket" {
  description = "Name of the private S3 files bucket"
  value       = module.files_bucket.s3_bucket_id
}

output "files_bucket_arn" {
  description = "ARN of the private S3 files bucket"
  value       = module.files_bucket.s3_bucket_arn
}

output "sqs_url" {
  description = "URL of the jobs SQS queue"
  value       = module.jobs_queue.queue_url
}

output "sqs_arn" {
  description = "ARN of the jobs SQS queue"
  value       = module.jobs_queue.queue_arn
}

output "app_secret_arn" {
  description = "ARN of the application secret"
  value       = module.app_secret.secret_arn
}

output "alb_logs_bucket" {
  description = "Name of the ALB access logs bucket"
  value       = module.alb_logs_bucket.s3_bucket_id
}