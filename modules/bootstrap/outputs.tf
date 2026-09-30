output "state_bucket_id" {
  description = "Name (id) of the S3 state bucket"
  value       = module.state_bucket.s3_bucket_id
}

output "state_bucket_arn" {
  description = "ARN of the S3 state bucket"
  value       = module.state_bucket.s3_bucket_arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB lock table"
  value       = module.lock_table.dynamodb_table_id
}