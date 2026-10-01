locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform {
  source = "../../../modules//edge"
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
    zone_id = "Z0000000000000000000"
  }
}

dependency "data" {
  config_path = "../20-data"
  mock_outputs = {
    kms_key_arn        = "arn:aws:kms:us-east-1:000000000000:key/mock"
    access_logs_bucket = "mock-access-logs"
  }
}

dependency "compute" {
  config_path = "../40-compute"
  mock_outputs = {
    alb_dns_name        = "mock-alb-000000000000.us-east-1.elb.amazonaws.com"
    acm_certificate_arn = "arn:aws:acm:us-east-1:000000000000:certificate/mock"
  }
}

inputs = {
  project     = "myapp"
  environment = local.env.environment
  domain      = local.env.domain
  tags        = local.env.tags

  zone_id               = dependency.network.outputs.zone_id
  kms_key_arn           = dependency.data.outputs.kms_key_arn
  alb_dns_name          = dependency.compute.outputs.alb_dns_name
  acm_certificate_arn   = dependency.compute.outputs.acm_certificate_arn
  account_id            = get_aws_account_id()
  backup_retention_days = local.env.backup_retention_days
  access_logs_bucket    = dependency.data.outputs.access_logs_bucket
}