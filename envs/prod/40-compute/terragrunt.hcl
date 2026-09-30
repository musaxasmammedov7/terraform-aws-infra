locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "../../../modules//compute"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

dependency "network" {
  config_path = "../10-network"
  mock_outputs = {
    vpc_id          = "vpc-00000000000000000"
    vpc_cidr_block  = "10.0.0.0/16"
    public_subnets  = ["subnet-00000000000000000", "subnet-00000000000000001"]
    private_subnets = ["subnet-00000000000000002", "subnet-00000000000000003"]
    alb_sg_id       = "sg-00000000000000000"
    app_sg_id       = "sg-00000000000000001"
    workers_sg_id   = "sg-00000000000000002"
    zone_id         = "Z0000000000000000000"
  }
}

dependency "iam" {
  config_path = "../30-iam"
  mock_outputs = {
    frontend_instance_profile_arn = "arn:aws:iam::000000000000:instance-profile/mock-frontend"
    backend_instance_profile_arn  = "arn:aws:iam::000000000000:instance-profile/mock-backend"
    workers_instance_profile_arn  = "arn:aws:iam::000000000000:instance-profile/mock-workers"
  }
}

dependency "data" {
  config_path = "../20-data"
  mock_outputs = {
    db_host              = "mock-db.cluster-000000000000.us-east-1.rds.amazonaws.com"
    db_port              = 5432
    sqs_url              = "https://sqs.us-east-1.amazonaws.com/000000000000/mock-jobs"
    files_bucket         = "mock-files"
    kms_key_arn          = "arn:aws:kms:us-east-1:000000000000:key/mock"
    db_master_secret_arn = "arn:aws:secretsmanager:us-east-1:000000000000:secret:mock"
    alb_logs_bucket      = "mock-alb-logs"
  }
}

inputs = {
  project     = "myapp"
  environment = local.env.environment
  domain      = local.env.domain
  tags        = local.env.tags

  vpc_id          = dependency.network.outputs.vpc_id
  vpc_cidr_block  = dependency.network.outputs.vpc_cidr_block
  public_subnets  = dependency.network.outputs.public_subnets
  private_subnets = dependency.network.outputs.private_subnets
  alb_sg_id       = dependency.network.outputs.alb_sg_id
  app_sg_id       = dependency.network.outputs.app_sg_id
  workers_sg_id   = dependency.network.outputs.workers_sg_id
  zone_id         = dependency.network.outputs.zone_id

  frontend_instance_profile_arn = dependency.iam.outputs.frontend_instance_profile_arn
  backend_instance_profile_arn  = dependency.iam.outputs.backend_instance_profile_arn
  workers_instance_profile_arn  = dependency.iam.outputs.workers_instance_profile_arn

  db_host              = dependency.data.outputs.db_host
  db_port              = dependency.data.outputs.db_port
  sqs_url              = dependency.data.outputs.sqs_url
  files_bucket         = dependency.data.outputs.files_bucket
  kms_key_arn          = dependency.data.outputs.kms_key_arn
  db_master_secret_arn = dependency.data.outputs.db_master_secret_arn
  alb_logs_bucket      = dependency.data.outputs.alb_logs_bucket

  frontend_instance_type = local.env.frontend_instance_type
  backend_instance_type  = local.env.backend_instance_type
  workers_instance_type  = local.env.workers_instance_type

  frontend_min_size = local.env.frontend_min_size
  frontend_max_size = local.env.frontend_max_size
  frontend_desired  = local.env.frontend_desired

  backend_min_size = local.env.backend_min_size
  backend_max_size = local.env.backend_max_size
  backend_desired  = local.env.backend_desired

  workers_min_size = local.env.workers_min_size
  workers_max_size = local.env.workers_max_size
  workers_desired  = local.env.workers_desired
}