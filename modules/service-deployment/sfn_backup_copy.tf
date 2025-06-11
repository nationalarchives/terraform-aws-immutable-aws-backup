locals {
  backup_copier_sfn_name = "${local.central_account_resource_name_prefix}-backup-copier"
}

#
# Step Function to copy backups between vaults
#
module "backup_copier_sfn_role" {
  source = "../iam-role"

  name = local.backup_copier_sfn_name
  assume_role_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Effect = "Allow"
        Principal : {
          Service : "states.amazonaws.com"
        }
        Action : "sts:AssumeRole",
        Condition : {
          StringEquals : {
            "aws:SourceAccount" : data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
  inline_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        "Sid" : "AllowLogDelivery",
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogDelivery",
          "logs:CreateLogStream",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutLogEvents",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "AllowGetTags",
        "Effect" : "Allow",
        "Action" : [
          "backup-gateway:ListTagsForResource",
          "dsql:ListTagsForResource",
          "dynamodb:ListTagsOfResource",
          "ec2:DescribeTags",
          "elasticfilesystem:DescribeTags",
          "fsx:ListTagsForResource",
          "fsx:ListTagsForResource",
          "rds:ListTagsForResource",
          "redshift-serverless:ListTagsForResource",
          "redshift:DescribeTags",
          "s3:GetBucketTagging",
          "s3:GetObjectTagging",
          "s3:GetObjectVersionTagging",
          "ssm-sap:ListTagsForResource",
          "storagegateway:ListTagsForResource",
          "timestream:ListTagsForResource",
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "AllowBackupCopyJob",
        "Effect" : "Allow",
        "Action" : [
          "backup:DescribeCopyJob",
          "backup:StartCopyJob",
          "backup:ListTags"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "AllowBackupVaultAccess",
        "Effect" : "Allow",
        "Action" : [
          "backup:DescribeBackupVault",
          "backup:ListRecoveryPointsByBackupVault"
        ],
        "Resource" : [
          local.current_standard_vault.arn,
          aws_backup_vault.intermediate.arn
        ]
      },
      {
        "Sid" : "AllowPassRole",
        "Effect" : "Allow",
        "Action" : [
          "iam:PassRole"
        ],
        "Resource" : var.central_backup_service_role_arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "backup_copier" {
  name              = "/aws/vendedlogs/states/${local.backup_copier_sfn_name}"
  retention_in_days = 90
}

resource "aws_sfn_state_machine" "backup_copier" {
  name     = local.backup_copier_sfn_name
  role_arn = module.backup_copier_sfn_role.role.arn
  type     = "EXPRESS"

  logging_configuration {
    level                  = "ALL"
    include_execution_data = true
    log_destination        = "${aws_cloudwatch_log_group.backup_copier.arn}:*"
  }

  definition = jsonencode({
    "QueryLanguage" : "JSONata"
    "StartAt" : "GetRecoveryPointTags",
    "States" : {
      "GetRecoveryPointTags" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:listTags",
        "Arguments" : {
          "ResourceArn" : "{% $states.input.detail.destinationRecoveryPointArn %}"
        },
        "Output" : "{% $merge([$states.input, { \"${local.delete_after_days_tag}\": $number($states.result.Tags.${local.delete_after_days_tag}) }]) %}"
        "Next" : "StartCopyJob"
      },
      "StartCopyJob" : {
        "Type" : "Task",
        "Arguments" : {
          "DestinationBackupVaultArn" : local.current_standard_vault.arn,
          "IamRoleArn" : var.central_backup_service_role_arn,
          "RecoveryPointArn" : "{% $states.input.detail.destinationRecoveryPointArn %}",
          "SourceBackupVaultName" : "{% $match($states.input.detail.destinationBackupVaultArn, /backup-vault:([^:]*)/).groups[0] %}",
          "Lifecycle" : {
            "DeleteAfterDays" : "{% $states.input.${local.delete_after_days_tag} %}"
          },
        },
        "Resource" : "arn:aws:states:::aws-sdk:backup:startCopyJob",
        "End" : true
      }
    },
  })
}

#
# EventBridge Rule to trigger the Step Function
#
module "backup_copier_eventbridge_role" {
  source = "../iam-role"

  name = "${local.backup_copier_sfn_name}-eventbridge"
  assume_role_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Effect = "Allow"
        Principal : {
          Service : "events.amazonaws.com"
        }
        Action : "sts:AssumeRole",
        Condition : {
          StringEquals : {
            "aws:SourceAccount" : data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
  inline_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Effect : "Allow",
        Action : "states:StartExecution",
        Resource : aws_sfn_state_machine.backup_copier.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "backup_copier" {
  name           = local.backup_copier_sfn_name
  event_bus_name = aws_cloudwatch_event_bus.event_bus.name
  description    = "Triggers the ${aws_sfn_state_machine.backup_copier.name} Step Function on backup copy job to/from specific vaults."

  event_pattern = jsonencode({
    "source" : ["aws.backup"],
    "detail-type" : ["Copy Job State Change"],
    "detail" : {
      "state" : ["COMPLETED"],
      "$or" : [
        { "sourceBackupVaultArn" : ["arn:aws:backup:us-east-1:123456789012:backup-vault:846869de-4589-45c3-ab60-4fbbabcdd3e"] },
        { "destinationBackupVaultArn" : [aws_backup_vault.intermediate.arn] }
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "backup_copier" {
  arn            = aws_sfn_state_machine.backup_copier.arn
  event_bus_name = aws_cloudwatch_event_rule.backup_copier.event_bus_name
  role_arn       = module.backup_copier_eventbridge_role.role.arn
  rule           = aws_cloudwatch_event_rule.backup_copier.name
}
