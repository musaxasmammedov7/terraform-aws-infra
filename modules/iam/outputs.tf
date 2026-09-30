output "frontend_role_arn" {
  description = "ARN of the frontend IAM role"
  value       = module.frontend_role.arn
}

output "frontend_instance_profile_name" {
  description = "Name of the frontend instance profile"
  value       = module.frontend_role.instance_profile_name
}

output "frontend_instance_profile_arn" {
  description = "ARN of the frontend instance profile"
  value       = module.frontend_role.instance_profile_arn
}

output "backend_role_arn" {
  description = "ARN of the backend IAM role"
  value       = module.backend_role.arn
}

output "backend_instance_profile_name" {
  description = "Name of the backend instance profile"
  value       = module.backend_role.instance_profile_name
}

output "backend_instance_profile_arn" {
  description = "ARN of the backend instance profile"
  value       = module.backend_role.instance_profile_arn
}

output "workers_role_arn" {
  description = "ARN of the workers IAM role"
  value       = module.workers_role.arn
}

output "workers_instance_profile_name" {
  description = "Name of the workers instance profile"
  value       = module.workers_role.instance_profile_name
}

output "workers_instance_profile_arn" {
  description = "ARN of the workers instance profile"
  value       = module.workers_role.instance_profile_arn
}