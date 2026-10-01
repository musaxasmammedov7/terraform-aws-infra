output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.this.name
}

output "config_bucket" {
  description = "Name of the AWS Config delivery bucket"
  value       = module.config_bucket.s3_bucket_id
}

output "securityhub_arn" {
  description = "ARN of the Security Hub account"
  value       = aws_securityhub_account.this.id
}

output "sns_topic_arn" {
  description = "ARN of the Security Hub alert SNS topic"
  value       = module.sns_security_alerts.topic_arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule that forwards findings to SNS"
  value       = module.eventbridge_securityhub.eventbridge_rule_arns["securityhub-findings"]
}