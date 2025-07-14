output "regions" {
  value = { for region in var.deployment_regions : region => module.region[region] }
}

output "aggregated" {
  value = {
    event_bus = [for i in values(module.region) : i.event_bus]
  }
}
