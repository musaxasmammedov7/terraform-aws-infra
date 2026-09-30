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

# Bootstrap creates the S3 bucket + DynamoDB table, but its own state must
# not live in that bucket (chicken-and-egg). Keep it local.
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "terraform.tfstate"
  }
}

inputs = {
  project     = "myapp"
  environment = local.env.environment
  region      = "us-east-1"
  account_id  = get_aws_account_id()
  tags        = local.env.tags
}