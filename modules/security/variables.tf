variable "project" {
  description = "Project/application name"
  type        = string
}

variable "environment" {
  description = "Environment name (test, prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
}

variable "kms_key_arn" {
  description = "ARN of the master KMS key (from the data layer) - encrypts the Config bucket"
  type        = string
}

variable "email" {
  description = "Email address for Security Hub notifications (SNS subscription)"
  type        = string
}