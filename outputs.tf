output "deployments" {
  value = { for service_name, deployment in var.deployments : service_name => merge(deployment, module.service_deployment[service_name]) }
}
