output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "azs" {
  description = "List of availability zones"
  value       = module.vpc.azs
}

output "public_subnets" {
  description = "List of public subnet IDs (ALB + NAT)"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of private app subnet IDs (EC2)"
  value       = module.vpc.private_subnets
}

output "database_subnets" {
  description = "List of database subnet IDs (RDS)"
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "Name of the RDS database subnet group"
  value       = module.vpc.database_subnet_group_name
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = module.vpc.private_route_table_ids
}

output "natgw_ids" {
  description = "List of NAT Gateway IDs (one per AZ)"
  value       = module.vpc.natgw_ids
}

output "igw_id" {
  description = "The ID of the Internet Gateway"
  value       = module.vpc.igw_id
}

output "zone_id" {
  description = "The ID of the Route53 hosted zone"
  value       = module.route53_zone.id
}

output "alb_sg_id" {
  description = "Security group ID of the ALB"
  value       = module.alb_sg.id
}

output "app_sg_id" {
  description = "Security group ID of the app instances"
  value       = module.app_sg.id
}

output "workers_sg_id" {
  description = "Security group ID of the worker instances"
  value       = module.workers_sg.id
}

output "db_sg_id" {
  description = "Security group ID of the database"
  value       = module.db_sg.id
}