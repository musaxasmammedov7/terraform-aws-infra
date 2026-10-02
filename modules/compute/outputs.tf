output "acm_certificate_arn" {
  description = "ARN of the ACM certificate (used by CloudFront); empty without a custom domain"
  value       = try(module.acm[0].acm_certificate_arn, "")
}

output "alb_dns_name" {
  description = "DNS name of the ALB (origin for CloudFront)"
  value       = module.alb.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = module.alb.arn
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of the ALB"
  value       = module.alb.zone_id
}

output "frontend_asg_name" {
  description = "Name of the frontend Auto Scaling Group"
  value       = module.asg_frontend.autoscaling_group_name
}

output "backend_asg_name" {
  description = "Name of the backend Auto Scaling Group"
  value       = module.asg_backend.autoscaling_group_name
}

output "workers_asg_name" {
  description = "Name of the workers Auto Scaling Group"
  value       = module.asg_workers.autoscaling_group_name
}