#
# Role to forward events from the local default event bus to the service event bus
#
module "default_to_event_bus_role" {
  source = "../iam-role"

  name = "default-to-${local.event_bus_name}-event-bus"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action = "sts:AssumeRole",
      Condition = {
        StringEquals = {
          "aws:SourceAccount" : local.account_id
        }
      }
    }]
  })
  inline_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Effect : "Allow",
        Action : "events:PutEvents",
        Resource : [for i in var.deployment_regions : "arn:${local.partition_id}:events:${i}:${local.account_id}:event-bus/${local.event_bus_name}"],
      }
    ]
  })
}
