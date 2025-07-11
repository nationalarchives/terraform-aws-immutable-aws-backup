output "regions" {
  value = { for region in var.deployment_regions : region => module.service_deployment_regional[region] }
}

output "aggregated" {
  value = {
    event_bus = [for i in values(module.service_deployment_regional) : i.event_bus]
  }
}
