################################################################################
# Instance Group
################################################################################

output "group_cluster_arn" {
  description = "The ARN of the cluster"
  value       = module.emr_instance_group.cluster_arn
}

output "group_cluster_id" {
  description = "The ID of the cluster"
  value       = module.emr_instance_group.cluster_id
}

output "group_cluster_core_instance_group_id" {
  description = "Core node type Instance Group ID, if using Instance Group for this node type"
  value       = module.emr_instance_group.cluster_core_instance_group_id
}

output "group_cluster_master_instance_group_id" {
  description = "Master node type Instance Group ID, if using Instance Group for this node type"
  value       = module.emr_instance_group.cluster_master_instance_group_id
}

output "group_cluster_master_public_dns" {
  description = "The DNS name of the master node. If the cluster is on a private subnet, this is the private DNS name. On a public subnet, this is the public DNS name"
  value       = module.emr_instance_group.cluster_master_public_dns
}

output "group_security_configuration_id" {
  description = "The ID of the security configuration"
  value       = module.emr_instance_group.security_configuration_id
}

output "group_security_configuration_name" {
  description = "The name of the security configuration"
  value       = module.emr_instance_group.security_configuration_name
}

output "group_service_iam_role_name" {
  description = "Service IAM role name"
  value       = module.emr_instance_group.service_iam_role_name
}

output "group_service_iam_role_arn" {
  description = "Service IAM role ARN"
  value       = module.emr_instance_group.service_iam_role_arn
}

output "group_service_iam_role_unique_id" {
  description = "Stable and unique string identifying the service IAM role"
  value       = module.emr_instance_group.service_iam_role_unique_id
}

output "group_autoscaling_iam_role_name" {
  description = "Autoscaling IAM role name"
  value       = module.emr_instance_group.autoscaling_iam_role_name
}

output "group_autoscaling_iam_role_arn" {
  description = "Autoscaling IAM role ARN"
  value       = module.emr_instance_group.autoscaling_iam_role_arn
}

output "group_autoscaling_iam_role_unique_id" {
  description = "Stable and unique string identifying the autoscaling IAM role"
  value       = module.emr_instance_group.autoscaling_iam_role_unique_id
}
