output "deployments" {
  value = { for service_name, deployment in var.deployments : service_name => merge(deployment, module.deployment[service_name]) }
}
