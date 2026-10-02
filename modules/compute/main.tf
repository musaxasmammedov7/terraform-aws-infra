# =====================================================================
# Compute layer
# ACM certificate, internet-facing ALB, three Auto Scaling Groups
# (frontend / backend / workers) and CloudWatch alarms.
#
# Depends on: network (subnets, SGs, DNS zone), iam (instance profiles),
#             data (RDS endpoint, SQS URL, S3 bucket, KMS key).
# =====================================================================

locals {
  name = "${var.project}-${var.environment}"

  # With a real domain: HTTPS listener + HTTP->HTTPS redirect.
  # Without a domain (domain == ""): plain HTTP listener - CloudFront
  # serves HTTPS on its own default certificate instead.
  https_listener = var.domain != "" ? {
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = module.acm[0].acm_certificate_arn
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"

      forward = {
        target_group_key = "frontend"
      }

      rules = {
        api = {
          priority = 10
          actions = [
            { forward = { target_group_key = "backend" } }
          ]
          conditions = [
            { path_pattern = { values = ["/api/*"] } }
          ]
        }
      }
    }
  } : {}

  http_redirect_listener = var.domain != "" ? {
    http-redirect = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  } : {}

  http_forward_listener = var.domain != "" ? {} : {
    http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "frontend"
      }

      rules = {
        api = {
          priority = 10
          actions = [
            { forward = { target_group_key = "backend" } }
          ]
          conditions = [
            { path_pattern = { values = ["/api/*"] } }
          ]
        }
      }
    }
  }

  http_listener = merge(local.http_redirect_listener, local.http_forward_listener)

  alb_listeners = merge(local.http_listener, local.https_listener)
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

# ---------------------------------------------------------------------
# ACM certificate (us-east-1, required for CloudFront), DNS validation
# via the Route53 zone created in the network layer.
# ---------------------------------------------------------------------
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "6.3.1"

  # ACM is only needed for a custom domain; without one CloudFront uses its
  # default certificate.
  count = var.domain != "" ? 1 : 0

  domain_name               = var.domain
  zone_id                   = var.zone_id
  subject_alternative_names = ["*.${var.domain}"]
  wait_for_validation       = true

  tags = var.tags
}

# ---------------------------------------------------------------------
# Application Load Balancer (internet-facing, in the public subnets)
#   - HTTPS listener with ACM certificate
#   - HTTP -> HTTPS redirect
#   - path-based routing: /api/* -> backend, everything else -> frontend
# ---------------------------------------------------------------------
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.1"

  name            = "${local.name}-alb"
  vpc_id          = var.vpc_id
  subnets         = var.public_subnets
  security_groups = [var.alb_sg_id]
  internal        = false

  enable_deletion_protection = true
  drop_invalid_header_fields = true
  idle_timeout               = 60
  enable_http2               = true

  # NOTE: ALB access logs are disabled - the -alb-logs bucket's delivery
  # policy requires an x-amz-acl header that conflicts with
  # BucketOwnerEnforced. Server access logging on the bucket itself already
  # covers FSBP S3.9.

  listeners = local.alb_listeners

  target_groups = {
    frontend = {
      name_prefix = "fe"
      protocol    = "HTTP"
      port        = 80
      target_type = "instance"
      vpc_id      = var.vpc_id

      # ASGs attach themselves via traffic_source_attachments
      create_attachment = false

      health_check = {
        enabled             = true
        healthy_threshold   = 3
        unhealthy_threshold = 3
        interval            = 30
        timeout             = 5
        path                = "/"
        matcher             = "200"
        protocol            = "HTTP"
      }
    }
    backend = {
      name_prefix = "be"
      protocol    = "HTTP"
      port        = 80
      target_type = "instance"
      vpc_id      = var.vpc_id

      # ASGs attach themselves via traffic_source_attachments
      create_attachment = false

      health_check = {
        enabled             = true
        healthy_threshold   = 3
        unhealthy_threshold = 3
        interval            = 30
        timeout             = 5
        path                = "/api/health"
        matcher             = "200"
        protocol            = "HTTP"
      }
    }
  }

  tags = var.tags
}

# =====================================================================
# Auto Scaling Groups
#   - EC2 instances in PRIVATE subnets, no public IP
#   - EBS volumes encrypted with the master KMS key
#   - IMDSv2 required (defense against SSRF)
#   - SSM-managed instances (IAM instance profiles from the iam layer)
# =====================================================================

module "asg_frontend" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.3.2"

  name                 = "${local.name}-frontend"
  launch_template_name = "${local.name}-frontend-lt"

  image_id          = data.aws_ami.amazon_linux_2023.id
  instance_type     = var.frontend_instance_type
  ebs_optimized     = true
  enable_monitoring = true

  security_groups     = [var.app_sg_id]
  vpc_zone_identifier = var.private_subnets

  create_iam_instance_profile = false
  iam_instance_profile_arn    = var.frontend_instance_profile_arn

  # Instances stay private - SSM handles administration
  metadata_options = {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings = [
    {
      device_name = "/dev/xvda"
      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 20
        volume_type           = "gp3"
      }
    }
  ]

  user_data = base64encode(templatefile("${path.module}/user_data_frontend.sh.tftpl", {
    project     = var.project
    environment = var.environment
    region      = var.region
  }))

  min_size         = var.frontend_min_size
  max_size         = var.frontend_max_size
  desired_capacity = var.frontend_desired

  health_check_type         = "ELB"
  health_check_grace_period = 300

  traffic_source_attachments = {
    alb = {
      traffic_source_identifier = module.alb.target_groups["frontend"].arn
      traffic_source_type       = "elbv2"
    }
  }

  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
      max_healthy_percentage = 100
    }
    triggers = ["tag"]
  }

  scaling_policies = {
    cpu = {
      policy_type = "TargetTrackingScaling"
      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
        target_value = 60.0
      }
    }
  }

  tags = var.tags
}

module "asg_backend" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.3.2"

  name                 = "${local.name}-backend"
  launch_template_name = "${local.name}-backend-lt"

  image_id          = data.aws_ami.amazon_linux_2023.id
  instance_type     = var.backend_instance_type
  ebs_optimized     = true
  enable_monitoring = true

  security_groups     = [var.app_sg_id]
  vpc_zone_identifier = var.private_subnets

  create_iam_instance_profile = false
  iam_instance_profile_arn    = var.backend_instance_profile_arn

  metadata_options = {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings = [
    {
      device_name = "/dev/xvda"
      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 20
        volume_type           = "gp3"
      }
    }
  ]

  user_data = base64encode(templatefile("${path.module}/user_data_backend.sh.tftpl", {
    project     = var.project
    environment = var.environment
    region      = var.region
  }))

  min_size         = var.backend_min_size
  max_size         = var.backend_max_size
  desired_capacity = var.backend_desired

  health_check_type         = "ELB"
  health_check_grace_period = 300

  traffic_source_attachments = {
    alb = {
      traffic_source_identifier = module.alb.target_groups["backend"].arn
      traffic_source_type       = "elbv2"
    }
  }

  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
      max_healthy_percentage = 100
    }
    triggers = ["tag"]
  }

  scaling_policies = {
    cpu = {
      policy_type = "TargetTrackingScaling"
      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
        target_value = 60.0
      }
    }
  }

  tags = var.tags
}

# Workers: SQS-driven, not attached to the ALB (health check type = EC2)
module "asg_workers" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.3.2"

  name                 = "${local.name}-workers"
  launch_template_name = "${local.name}-workers-lt"

  image_id          = data.aws_ami.amazon_linux_2023.id
  instance_type     = var.workers_instance_type
  ebs_optimized     = true
  enable_monitoring = true

  security_groups     = [var.workers_sg_id]
  vpc_zone_identifier = var.private_subnets

  create_iam_instance_profile = false
  iam_instance_profile_arn    = var.workers_instance_profile_arn

  metadata_options = {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings = [
    {
      device_name = "/dev/xvda"
      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 20
        volume_type           = "gp3"
      }
    }
  ]

  user_data = base64encode(templatefile("${path.module}/user_data_workers.sh.tftpl", {
    project     = var.project
    environment = var.environment
    region      = var.region
  }))

  min_size         = var.workers_min_size
  max_size         = var.workers_max_size
  desired_capacity = var.workers_desired

  health_check_type         = "EC2"
  health_check_grace_period = 300

  instance_refresh = {
    strategy = "Rolling"
    preferences = {
      min_healthy_percentage = 50
      max_healthy_percentage = 100
    }
    triggers = ["tag"]
  }

  scaling_policies = {
    cpu = {
      policy_type = "TargetTrackingScaling"
      target_tracking_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ASGAverageCPUUtilization"
        }
        target_value = 60.0
      }
    }
  }

  tags = var.tags
}

# =====================================================================
# CloudWatch alarms (observability)
# =====================================================================
module "alb_5xx_alarm" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "5.7.3"

  alarm_name          = "${local.name}-alb-5xx"
  alarm_description   = "ALB returned 5xx errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 0
  period              = "60"
  statistic           = "Sum"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }
}

module "alb_unhealthy_hosts_alarm" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "5.7.3"

  alarm_name          = "${local.name}-alb-unhealthy-hosts"
  alarm_description   = "ALB has unhealthy target hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 0
  period              = "60"
  statistic           = "Average"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }
}

module "backend_cpu_alarm" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "5.7.3"

  alarm_name          = "${local.name}-backend-cpu"
  alarm_description   = "Backend ASG CPU utilization too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 80
  period              = "300"
  statistic           = "Average"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = module.asg_backend.autoscaling_group_name
  }
}

module "workers_cpu_alarm" {
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "5.7.3"

  alarm_name          = "${local.name}-workers-cpu"
  alarm_description   = "Workers ASG CPU utilization too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 80
  period              = "300"
  statistic           = "Average"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = module.asg_workers.autoscaling_group_name
  }
}

