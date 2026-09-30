# =====================================================================
# Network layer
# Implements the network part of the architecture diagram:
#   - VPC with public / private (app) / database (data) subnets across 2 AZ
#   - Internet Gateway + one NAT Gateway per AZ
#   - Route tables:
#       Public  : local + 0.0.0.0/0 -> IGW
#       Private : local + S3 prefix list -> S3 Gateway endpoint + 0.0.0.0/0 -> NAT
#       Data    : local only
#   - VPC endpoints: S3 (Gateway) + SSM / SSMMessages / EC2Messages (Interface)
#   - Security groups per tier (CloudFront -> ALB -> App -> DB)
#   - Route53 hosted zone (created here so ACM/CloudFront can use it later)
# =====================================================================

#alb_sg egress ──► ссылка на app_sg
app_sg ingress ──► ссылка на alb_sg взаимные ссылки между двумя модулями. Terraform строит граф зависимостей, а модульные outputs тянут за собой весь модуль → получается цикл, который Terraform не может разрешить (при валидации ). 
#Поэтому одно направление (alb_sg → app) сделано через CIDR приватных подсетей — так цикл разрывается, а трафик всё равно доходит, потому что app-инстансы живут ровно в этих подсетях.

locals {
  name = "${var.project}-${var.environment}"

  # ALB egress targets the app subnets by CIDR instead of by SG reference.
  # This avoids a mutual SG-to-SG dependency (alb_sg <-> app_sg) which
  # Terraform cannot resolve across modules.
  alb_egress_to_app = {
    for i, cidr in var.private_subnets :
    "to-app-${i}" => {
      from_port   = 80
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = cidr
      description = "Egress to app subnet ${cidr}"
    }
  }
}

data "aws_ec2_managed_prefix_list" "cloudfront" {               # здесь берутся все айпишки cloudfront(edge nodes) 
  name = "com.amazonaws.global.cloudfront.origin-facing"       # с помощью функций или вешаем на alb waf
}

# ---------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = local.name
  cidr = var.vpc_cidr

  azs              = var.azs
  public_subnets   = var.public_subnets
  private_subnets  = var.private_subnets
  database_subnets = var.database_subnets

  # One NAT Gateway per AZ (architecture requirement)
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Observability: VPC flow logs to CloudWatch
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  # Security hardening: the default SG is not used by anything, lock it down
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  public_subnet_tags   = { Tier = "public" }
  private_subnet_tags  = { Tier = "private" }
  database_subnet_tags = { Tier = "database" }

  tags = var.tags
}

# ---------------------------------------------------------------------
# VPC endpoints
#   s3            -> Gateway endpoint attached to the private route tables
#                    (adds the "S3 prefix list" route to the Private RT)
#   ssm/ssmmessages/ec2messages -> Interface endpoints so SSM Session Manager
#                    works for instances that have no public IP
# ---------------------------------------------------------------------
module "endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "6.7.3"

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.endpoints_sg.id]

  endpoints = {
    s3 = {
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = "s3-gateway-endpoint" }
    }
    ssm = {                                                      #«контрольная плоскость»: инстанс регистрируется в SSM, тянет параметры и команды.
      service             = "ssm"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      tags                = { Name = "ssm-endpoint" }
    }
    ssmmessages = {                                              #сам канал сессии: по нему стримятся ввод/вывод между твоей консолью и инстансом (то, что ты видишь в Session Manager).
      service             = "ssmmessages"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      tags                = { Name = "ssmmessages-endpoint" }
    }
    ec2messages = {                                            # доставка команд агенту SSM на инстансе 
      service             = "ec2messages"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      tags                = { Name = "ec2messages-endpoint" }
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------
# Security groups
# Tier model exactly as in the diagram:
#   ALB 443  <- CloudFront (prefix list)
#   App 80/443 <- ALB
#   DB  5432 <- App + Workers
#   Workers: no inbound
# ---------------------------------------------------------------------

# VPC endpoints SG: allow HTTPS from anywhere inside the VPC
module "endpoints_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-vpc-endpoints"
  description = "Security group for VPC interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    https-from-vpc = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = module.vpc.vpc_cidr_block
      description = "HTTPS from within the VPC"
    }
  }
  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = var.tags
}

# ALB SG: accepts HTTPS only from CloudFront, forwards to app instances
module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-alb"
  description = "Security group for the internet-facing ALB"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    https-from-cloudfront = {
      from_port      = 443
      to_port        = 443
      ip_protocol    = "tcp"
      prefix_list_id = data.aws_ec2_managed_prefix_list.cloudfront.id
      description    = "HTTPS from CloudFront"
    }
  }
  egress_rules = local.alb_egress_to_app

  tags = var.tags
}

# App SG (frontend + backend instances): accepts traffic only from the ALB
module "app_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-app"
  description = "Security group for frontend and backend instances"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    http-from-alb = {
      from_port                    = 80
      to_port                      = 80
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb_sg.id
      description                  = "HTTP from ALB"
    }
    https-from-alb = {
      from_port                    = 443
      to_port                      = 443
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.alb_sg.id
      description                  = "HTTPS from ALB"
    }
    self = {
      ip_protocol                  = "-1"
      referenced_security_group_id = "self"
      description                  = "Instances within this group"
    }
  }
  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Egress to internet via NAT Gateway"
    }
  }

  tags = var.tags
}

# Workers SG: no inbound access, outbound only
module "workers_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-workers"
  description = "Security group for worker instances"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    self = {
      ip_protocol                  = "-1"
      referenced_security_group_id = "self"
    }
  }
  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Egress to internet via NAT Gateway"
    }
  }

  tags = var.tags
}

# DB SG: PostgreSQL only from app + workers
module "db_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"

  name        = "${local.name}-db"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    postgres-from-app = {
      from_port                    = 5432
      to_port                      = 5432
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.app_sg.id
      description                  = "PostgreSQL from app instances"
    }
    postgres-from-workers = {
      from_port                    = 5432
      to_port                      = 5432
      ip_protocol                  = "tcp"
      referenced_security_group_id = module.workers_sg.id
      description                  = "PostgreSQL from worker instances"
    }
  }
  egress_rules = {
    to-vpc = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
      description = "Egress within VPC"
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------
# Route53 hosted zone
# Created here (early) so ACM DNS validation and CloudFront records can
# reference it without circular dependencies between layers.
# ---------------------------------------------------------------------
module "route53_zone" {
  source  = "terraform-aws-modules/route53/aws"
  version = "6.5.1"

  create_zone = true
  name        = var.domain
  comment     = "Hosted zone for ${var.domain} (${var.environment})"

  tags = var.tags
}
