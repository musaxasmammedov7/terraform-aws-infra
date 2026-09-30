locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "../../../modules//data"
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
    vpc_id                     = "vpc-00000000000000000"
    database_subnet_group_name = "mock-db-subnet-group"
    db_sg_id                   = "sg-00000000000000000"
  }
}

dependency "iam" {
  config_path = "../30-iam"
  mock_outputs = {
    backend_role_arn = "arn:aws:iam::000000000000:role/mock-backend"
    workers_role_arn = "arn:aws:iam::000000000000:role/mock-workers"
  }
}

inputs = {
  project     = "myapp"
  environment = local.env.environment
  tags        = local.env.tags

  db_subnet_group_name = dependency.network.outputs.database_subnet_group_name
  db_sg_id             = dependency.network.outputs.db_sg_id

  backend_role_arn = dependency.iam.outputs.backend_role_arn
  workers_role_arn = dependency.iam.outputs.workers_role_arn

  db_instance_class       = local.env.db_instance_class
  db_name                 = local.env.db_name
  db_username             = local.env.db_username
  db_port                 = local.env.db_port
  backup_retention_period = local.env.backup_retention_period
}