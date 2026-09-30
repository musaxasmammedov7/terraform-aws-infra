locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "../../../modules//bootstrap"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

inputs = {
  project     = "myapp"
  environment = local.env.environment
  region      = "us-east-1"
  account_id  = get_aws_account_id()
  tags        = local.env.tags
}