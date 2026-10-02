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

variable "domain" {
  description = "Domain name for the application (Route53 hosted zone + ACM + CloudFront)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets (ALB + NAT)"
  type        = list(string)
}

variable "private_subnets" {
  description = "CIDR blocks for private app subnets (EC2 instances)"
  type        = list(string)
}

variable "database_subnets" {
  description = "CIDR blocks for private data subnets (RDS)"
  type        = list(string)
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
}