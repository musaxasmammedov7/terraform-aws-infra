# =====================================================================
# TEST environment configuration
# This file is included by every unit under envs/test/ and provides:
#   1. remote_state (S3 backend + DynamoDB lock, unique per env)
#   2. environment-specific locals (CIDRs, sizes, domain)
#   3. default inputs passed to every root module
# =====================================================================

locals {
  environment = "test"

  # -- Network ---------------------------------------------------------
  # Exactly as in the architecture diagram:
  #   Public  RT:  local + 0.0.0.0/0 -> IGW
  #   Private RT:  local + S3 prefix list -> S3 GW endpoint + 0.0.0.0/0 -> NAT
  #   Data    RT:  local only
  vpc_cidr         = "10.0.0.0/16"
  azs              = ["us-east-1a", "us-east-1b"]
  public_subnets   = ["10.0.101.0/24", "10.0.102.0/24"]
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24"]

  # -- Domain ----------------------------------------------------------
  # REPLACE with a domain you control (Route53 can host any zone).
  domain = "app-test.example.com"

  # -- Compute (EC2) ---------------------------------------------------
  frontend_instance_type = "t3.micro"
  backend_instance_type  = "t3.micro"
  workers_instance_type  = "t3.micro"

  frontend_min_size = 1
  frontend_max_size = 4
  frontend_desired  = 1

  backend_min_size = 1
  backend_max_size = 4
  backend_desired  = 1

  workers_min_size = 1
  workers_max_size = 4
  workers_desired  = 1

  # -- Database --------------------------------------------------------
  db_instance_class       = "db.t3.micro"
  db_name                 = "myapp"
  db_username             = "myapp"
  db_port                 = 5432
  backup_retention_period = 7
  backup_retention_days   = 14

  # -- Security --------------------------------------------------------
  security_email = "musaxasmammedov77@gmail.com" # уведомления Security Hub

  # -- Tags ------------------------------------------------------------
  tags = {
    Environment = "test"
    Project     = "myapp"
    Terraform   = "true"
  }
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "myapp-${local.environment}-terraform-state"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "myapp-${local.environment}-terraform-lock"
  }
}