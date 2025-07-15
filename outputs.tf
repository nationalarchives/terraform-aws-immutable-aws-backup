#
# Output module variables, like a resource.
#
output "central_account_resource_name_prefix" {
  description = "Prefix to be used for resource names in the central account."
  value       = var.central_account_resource_name_prefix
}

output "member_account_resource_name_prefix" {
  description = "Prefix to be used for resource names in member accounts."
  value       = var.member_account_resource_name_prefix
}

output "terraform_state_bucket_name" {
  description = "Name of the S3 bucket used for storing Terraform state files for custom Terraform deployments."
  value       = var.terraform_state_bucket_name
}


#
# Additional or modified outputs
#
output "deployments" {
  value = { for service_name, deployment in var.deployments : service_name => merge(deployment, module.deployment[service_name]) }
}
