#
# Event Bus for AWS Backup events from central and member accounts
#
resource "aws_cloudwatch_event_bus" "event_bus" {
  region = var.region
  name   = var.eventbridge.bus_name
}

resource "aws_cloudwatch_event_bus_policy" "event_bus" {
  region         = var.region
  event_bus_name = aws_cloudwatch_event_bus.event_bus.id
  policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Sid : "AllowPutEventsFromMemberAccounts",
        Principal : {
          AWS : "*"
        },
        Effect : "Allow",
        Action : ["events:PutEvents"]
        Resource : "*",
        Condition : {
          ArnLike : {
            "aws:PrincipalArn" : "arn:${var.current.partition}:iam::*:role/${var.deployment.member_account_eventbridge_rule_name}",
          },
          "ForAnyValue:StringLike" : {
            "aws:PrincipalOrgPaths" : var.deployment.ou_paths_including_children
          }
        }
      }
    ]
  })
}

#
# Log all events to CloudWatch Logs
#
resource "aws_cloudwatch_log_group" "event_bus" {
  region            = var.region
  name              = "/aws/events/${aws_cloudwatch_event_bus.event_bus.name}"
  retention_in_days = 90
}

resource "aws_cloudwatch_log_resource_policy" "policy" {
  region      = var.region
  policy_name = "${aws_cloudwatch_event_bus.event_bus.name}-event_bus_to_cloudwatch"
  policy_document = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
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
        "Resource" : "${aws_cloudwatch_log_group.event_bus.arn}:*"
      }
    ],
  })
}
resource "aws_cloudwatch_event_rule" "event_bus_to_cloudwatch" {
  region         = var.region
  name           = "log-to-cloudwatch"
  event_bus_name = aws_cloudwatch_event_bus.event_bus.name
  description    = "Logs all events to CloudWatch Logs."
  event_pattern  = jsonencode({ "source" : [{ "prefix" : "" }] })
}

resource "aws_cloudwatch_event_target" "event_bus_to_cloudwatch" {
  region         = var.region
  rule           = aws_cloudwatch_event_rule.event_bus_to_cloudwatch.name
  event_bus_name = aws_cloudwatch_event_bus.event_bus.name
  arn            = aws_cloudwatch_log_group.event_bus.arn
}

#
# Forward events from the local default event bus to the service event bus
#
resource "aws_cloudwatch_event_rule" "default_to_event_bus" {
  # This rule is replicated in the StackSet, make sure to update both places if changes are made.
  region      = var.region
  name        = "backup-events-to-${aws_cloudwatch_event_bus.event_bus.name}-event-bus"
  description = "Forwards AWS Backup events to the ${aws_cloudwatch_event_bus.event_bus.name} event bus."
  event_pattern = jsonencode({
    source : ["aws.backup"],
    "detail-type" : ["Backup Job State Change", "Copy Job State Change"],
    "detail" : {
      "$or" : [
        { "backupVaultName" : [var.deployment.member_account_backup_vault_name] },
        { "sourceBackupVaultArn" : local.central_backup_vault_arns },
        { "destinationBackupVaultArn" : local.central_backup_vault_arns }
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "default_to_event_bus" {
  region   = var.region
  rule     = aws_cloudwatch_event_rule.default_to_event_bus.name
  arn      = aws_cloudwatch_event_bus.event_bus.arn
  role_arn = var.eventbridge.forwarder_iam_role_arn
}
