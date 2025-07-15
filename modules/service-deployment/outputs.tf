output "regions" {
  description = "Map of regions to their respective outputs."
  value       = { for region in var.deployment_regions : region => module.region[region] }
}

output "event_buses" {
  description = "List of event buses created in each region."
  value       = [for i in values(module.region) : i.event_bus]
}
