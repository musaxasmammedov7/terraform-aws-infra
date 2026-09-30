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
  description = "Domain name for the application"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
}

# ---- Network (from network layer) ------------------------------------
variable "vpc_id" {
  type = string
}

variable "vpc_cidr_block" {
  type = string
}

variable "public_subnets" {
  type = list(string)
}

variable "private_subnets" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "app_sg_id" {
  type = string
}

variable "workers_sg_id" {
  type = string
}

variable "zone_id" {
  type = string
}

# ---- IAM (from iam layer) ---------------------------------------------
variable "frontend_instance_profile_arn" {
  type = string
}

variable "backend_instance_profile_arn" {
  type = string
}

variable "workers_instance_profile_arn" {
  type = string
}

# ---- Data (from data layer) -------------------------------------------
variable "db_host" {
  type = string
}

variable "db_port" {
  type = number
}

variable "sqs_url" {
  type = string
}

variable "files_bucket" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "db_master_secret_arn" {
  type = string
}

variable "alb_logs_bucket" {
  type = string
}

# ---- Instance sizing ---------------------------------------------------
variable "frontend_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "backend_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "workers_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "frontend_min_size" {
  type    = number
  default = 1
}

variable "frontend_max_size" {
  type    = number
  default = 4
}

variable "frontend_desired" {
  type    = number
  default = 1
}

variable "backend_min_size" {
  type    = number
  default = 1
}

variable "backend_max_size" {
  type    = number
  default = 4
}

variable "backend_desired" {
  type    = number
  default = 1
}

variable "workers_min_size" {
  type    = number
  default = 1
}

variable "workers_max_size" {
  type    = number
  default = 4
}

variable "workers_desired" {
  type    = number
  default = 1
}