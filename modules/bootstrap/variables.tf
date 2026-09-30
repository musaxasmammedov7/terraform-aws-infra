variable "project" {
  description = "Project/application name (used as a prefix for resources)"
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

variable "account_id" {
  description = "AWS account ID (used to guarantee bucket uniqueness)"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
}