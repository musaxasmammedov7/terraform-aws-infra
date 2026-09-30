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

variable "db_subnet_group_name" {
  description = "Name of the RDS database subnet group (from the network layer)"
  type        = string
}

variable "db_sg_id" {
  description = "Security group ID of the database (from the network layer)"
  type        = string
}

variable "backend_role_arn" {
  description = "ARN of the backend IAM role (from the iam layer)"
  type        = string
}

variable "workers_role_arn" {
  description = "ARN of the workers IAM role (from the iam layer)"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the database to create inside PostgreSQL"
  type        = string
  default     = "myapp"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "myapp"
}

variable "db_port" {
  description = "Port for PostgreSQL"
  type        = number
  default     = 5432
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}