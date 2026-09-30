# =====================================================================
# ROOT Terragrunt configuration
# This file is inherited by every unit (layer) in envs/<environment>/.
# It generates the AWS provider and sets global defaults.
# =====================================================================

locals {
  # Globals shared by all environments (override per-env in envs/*/env.hcl)
  project = "myapp"
  region  = "us-east-1"
}

# Generates provider.tf inside each unit so we don't duplicate it per layer.
# NOTE: a `generate` block can only use locals defined in the SAME file.
# The Environment tag is applied via `inputs.tags` (from env.hcl) in every
# root module instead.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.region}"

      default_tags {
        tags = {
          Project     = "${local.project}"
          ManagedBy   = "terragrunt"
        }
      }
    }
  EOF
}

# ---------------------------------------------------------------------
# NOTE on the remote_state block:
# It intentionally lives in envs/<environment>/env.hcl (not here) because
# the S3 bucket and DynamoDB table names must be unique per environment
# (test / prod). Keeping it in env.hcl gives us the `environment` local.
# ---------------------------------------------------------------------