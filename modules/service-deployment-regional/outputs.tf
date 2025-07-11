output "event_bus" {
  description = "The EventBridge Event Bus created for this deployment."
  value       = aws_cloudwatch_event_bus.event_bus
}
