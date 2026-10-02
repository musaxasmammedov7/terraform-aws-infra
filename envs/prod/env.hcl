# =====================================================================
# PROD environment configuration
# Same structure as test, but with production values.
# =====================================================================

locals {
  environment = "prod"

  # -- Network ---------------------------------------------------------
  vpc_cidr         = "10.0.0.0/16"
  azs              = ["us-east-1a", "us-east-1b"]
  public_subnets   = ["10.0.101.0/24", "10.0.102.0/24"]
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  database_subnets = ["10.0.21.0/24", "10.0.22.0/24"]

  # -- Domain ----------------------------------------------------------
  # REPLACE with a domain you control.
  domain = "app.example.com"

  # -- Compute (EC2) ---------------------------------------------------
  frontend_instance_type = "t3.small"
  backend_instance_type  = "t3.small"
  workers_instance_type  = "t3.small"

  frontend_min_size = 2
  frontend_max_size = 8
  frontend_desired  = 2

  backend_min_size = 2
  backend_max_size = 8
  backend_desired  = 2

  workers_min_size = 2
  workers_max_size = 8
  workers_desired  = 2

  # -- Database --------------------------------------------------------
  db_instance_class       = "db.t3.medium"
  db_name                 = "myapp"
  db_username             = "myapp"
  db_port                 = 5432
  backup_retention_period = 14
  multi_az              = true
  backup_retention_days   = 30

# -- Security --------------------------------------------------------
  security_email = "musaxasmammedov77@gmail.com"   # уведомления Security Hub
  enable_security_hub = true

  # -- Tags ------------------------------------------------------------
  tags = {
    Environment = "prod"
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