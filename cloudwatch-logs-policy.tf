# CloudWatch Logs allows a maximum of 10 resource policies per region per account, so a single policy
# covering the event bus log groups of all deployments is created per region instead of one per deployment.
resource "aws_cloudwatch_log_resource_policy" "event_bus_logs" {
  for_each = toset(local.deployment_regions)

  region      = each.value
  policy_name = "${var.central_account_resource_name_prefix}event-bus-to-cloudwatch"
  policy_document = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowEventBridgeToWriteBackupEventBusLogs",
        "Principal" : {
          "Service" : [
            "events.amazonaws.com",
            "delivery.logs.amazonaws.com"
          ]
        },
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        # Log group names must match those created in modules/service-deployment-regional/eventbridge.tf.
        "Resource" : [for service_name in keys(var.deployments) : "arn:${local.partition_id}:logs:${each.value}:${local.account_id}:log-group:/aws/events/${var.central_account_resource_name_prefix}${service_name}:*"]
      }
    ],
  })
}
