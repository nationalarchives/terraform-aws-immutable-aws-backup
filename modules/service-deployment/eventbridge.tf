#
# Event Bus for AWS Backup events from central and member accounts
#
resource "aws_cloudwatch_event_bus" "event_bus" {
  name = local.central_account_resource_name_prefix
}

resource "aws_cloudwatch_event_bus_policy" "event_bus" {
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
            "aws:PrincipalArn" : "arn:*:iam::*:role/${local.member_account_eventbridge_rule_name}",
          },
          "ForAnyValue:StringLike" : {
            "aws:PrincipalOrgPaths" : local.deployment_ou_paths_including_children
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
  name              = "/aws/events/${aws_cloudwatch_event_bus.event_bus.name}"
  retention_in_days = 90
}

resource "aws_cloudwatch_log_resource_policy" "policy" {
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
  name           = "log-to-cloudwatch"
  event_bus_name = aws_cloudwatch_event_bus.event_bus.name
  description    = "Logs all events to CloudWatch Logs."
  event_pattern  = jsonencode({ "source" : [{ "prefix" : "" }] })
}

resource "aws_cloudwatch_event_target" "example" {
  rule           = aws_cloudwatch_event_rule.event_bus_to_cloudwatch.name
  event_bus_name = aws_cloudwatch_event_bus.event_bus.name
  arn            = aws_cloudwatch_log_group.event_bus.arn
}

#
# Forward events from the local default event bus to the service event bus
#
module "default_to_event_bus_role" {
  source = "../iam-role"

  name = "default-to-${aws_cloudwatch_event_bus.event_bus.name}-event-bus"
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
        Resource : aws_cloudwatch_event_bus.event_bus.arn,
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "default_to_event_bus" {
  name        = "backup-events-to-${aws_cloudwatch_event_bus.event_bus.name}-event-bus"
  description = "Forwards AWS Backup events to the ${aws_cloudwatch_event_bus.event_bus.name} event bus."
  event_pattern = jsonencode({
    source : ["aws.backup"]
    "detail-type" : ["Backup Job State Change", "Copy Job State Change", "Restore Job State Change"]
  })
}

resource "aws_cloudwatch_event_target" "default_to_event_bus" {
  rule     = aws_cloudwatch_event_rule.default_to_event_bus.name
  arn      = aws_cloudwatch_event_bus.event_bus.arn
  role_arn = module.default_to_event_bus_role.role.arn
}
