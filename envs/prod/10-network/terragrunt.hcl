locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "../../../modules//network"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

inputs = {
  project          = "myapp"
  environment      = local.env.environment
  domain           = local.env.domain
  vpc_cidr         = local.env.vpc_cidr
  azs              = local.env.azs
  public_subnets   = local.env.public_subnets
  private_subnets  = local.env.private_subnets
  database_subnets = local.env.database_subnets
  tags             = local.env.tags
}