locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "../../../modules//security"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

dependency "data" {
  config_path = "../20-data"
  mock_outputs = {
    kms_key_arn = "arn:aws:kms:us-east-1:000000000000:key/mock"
  }
}

inputs = {
  project     = "myapp"
  environment = local.env.environment
  tags        = local.env.tags
  kms_key_arn = dependency.data.outputs.kms_key_arn
  email       = local.env.security_email
}