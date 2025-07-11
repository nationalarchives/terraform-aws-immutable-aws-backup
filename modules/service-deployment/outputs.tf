output "regions" {
  value = { for region in var.deployment_regions : region => module.region_deployment[region] }
}

output "aggregated" {
  value = {
    event_bus = [for i in values(module.region_deployment) : i.event_bus]
  }
}
