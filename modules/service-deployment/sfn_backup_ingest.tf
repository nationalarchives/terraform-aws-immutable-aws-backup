locals {
  backup_ingest_sfn_name = "${local.central_account_resource_name_prefix}-backup-ingest"
}

# This module creates the IAM role for the Step Function that orchestrates backup ingestion
module "member_backup_orchestration_role" {

  count  = var.create_member_account_resources ? 1 : 0
  source = "../iam-role" # Re-use your existing IAM role module


  name = local.member_backup_orchestration_role_name

  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
         
          AWS = module.central_sfn_orchestrator_role.role.arn
        },
        Action = "sts:AssumeRole",
      }
    ]
  })


  inline_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Sid" : "AllowUpdateRecoveryPointLifecycle",
        "Effect" : "Allow",
        "Action" : "backup:UpdateRecoveryPointLifecycle",
        "Resource" : "*"
      },
      {
        "Sid" : "AllowGetTags",
        "Effect" : "Allow",
        "Action" : [
          "backup-gateway:ListTagsForResource", "dsql:ListTagsForResource", "dynamodb:ListTagsOfResource",
          "ec2:DescribeTags", "elasticfilesystem:DescribeTags", "fsx:ListTagsForResource",
          "rds:ListTagsForResource", "redshift-serverless:ListTagsForResource", "redshift:DescribeTags",
          "s3:GetBucketTagging", "s3:GetObjectTagging", "s3:GetObjectVersionTagging",
          "ssm-sap:ListTagsForResource", "storagegateway:ListTagsForResource", "timestream:ListTagsForResource",
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
          "arn:${local.partition_id}:backup:${var.region}:${local.account_id}:backup-vault/*"
        ]
      }
    ]
  })
}




#
# Step Function to copy backups between vaults
#
module "backup_ingest_sfn_role" {
  source = "../iam-role"

  name = "${local.backup_ingest_sfn_name}-sfn"
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
            "aws:SourceAccount" : local.account_id
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
          "backup:UpdateRecoveryPointLifecycle",
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
      },
      {
        Sid : "AllowAssumeRoleInMemberAccounts",
        Effect : "Allow",
        Action : [
          "sts:AssumeRole"
        ],
        Resource : "arn:aws:iam::*:role/${local.member_account_backup_service_role_name}",
        Condition : {
          "ForAnyValue:StringLike" : {
            "aws:ResourceOrgPaths" : local.deployment_ou_paths_including_children
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "backup_ingest" {
  name              = "/aws/vendedlogs/states/${local.backup_ingest_sfn_name}"
  retention_in_days = 90
}

resource "aws_sfn_state_machine" "backup_ingest" {
  name     = local.backup_ingest_sfn_name
  role_arn = module.backup_ingest_sfn_role.role.arn
  type     = "EXPRESS"

  logging_configuration {
    level                  = "ALL"
    include_execution_data = true
    log_destination        = "${aws_cloudwatch_log_group.backup_ingest.arn}:*"
  }

  definition = jsonencode({
    "QueryLanguage" : "JSONata"
    "StartAt" : "SetVars",
    "States" : {
      "SetVars" : {
        "Type" : "Pass",
        "Output" : "", # Don't output anything to reduce CloudWatch Logs ingest
        "Assign" : {
          "accountId" : local.account_id,
          "centralBackupServiceRoleArn" : var.central_backup_service_role_arn,
          "destinationBackupVaultArn" : "{% $states.input.detail.destinationBackupVaultArn %}",
          "destinationRecoveryPointArn" : "{% $states.input.detail.destinationRecoveryPointArn %}",
          "intermediateBackupVaultArn" : aws_backup_vault.intermediate.arn,
          "jobStatus" : "{% $states.input.detail.state %}",
          "lagBackupVaultNamePrefix" : local.lag_vault_prefix,
          "memberAccountBackupServiceRoleName" : local.member_account_backup_service_role_name,
          "partitionId" : local.partition_id,
          "retentionTags" : {
            "member" : local.local_retention_days_tag,
            "intermediate" : local.intermediate_retention_days_tag,
          },
          "sourceAccountNumber" : "{% $states.input.account %}",
          "sourceBackupVaultArn" : "{% $states.input.detail.sourceBackupVaultArn %}",
          "sourceRecoveryPointArn" : "{% $states.input.resources[0] %}",
          "standardBackupVaultArn" : local.current_standard_vault.arn,
          "standardBackupVaultNamePrefix" : local.standard_vault_prefix,
        },
        "Next" : "CalculateVars"
      },
      "CalculateVars" : {
        "Type" : "Pass",
        "Output" : "{% $states.input %}",
        "Assign" : {
          "destinationBackupVaultName" : "{% $match($destinationBackupVaultArn, /backup-vault:([^:]*)/).groups[0] %}",
          "sourceAccountBackupServiceRoleArn" : "{% 'arn:' & $partitionId & ':iam::' & $sourceAccountNumber & ':role/' & $memberAccountBackupServiceRoleName %}",
          "sourceBackupVaultName" : "{% $match($sourceBackupVaultArn, /backup-vault:([^:]*)/).groups[0] %}",
        },
        "Next" : "EventType?"
      },
      "EventType?" : {
        "Type" : "Choice",
        "Choices" : [
          {
            "Comment" : "Successful Member -> Intermediate",
            "Condition" : "{% $jobStatus = 'COMPLETED' and $sourceAccountNumber != $accountId and $destinationBackupVaultArn = $intermediateBackupVaultArn %}",
            "Assign" : {
              "sourceBackupVaultType" : "member",
            },
            "Next" : "StartCopyToStandardVault"
          },
          {
            "Comment" : "Successful Intermediate -> Standard",
            "Condition" : "{% $jobStatus = 'COMPLETED' and $sourceBackupVaultArn = $intermediateBackupVaultArn and $substring($destinationBackupVaultName, 0, $length($standardBackupVaultNamePrefix)) = $standardBackupVaultNamePrefix %}",
            "Assign" : {
              "sourceBackupVaultType" : "intermediate",
            },
            "Next" : "GetDestinationRecoveryPointTags"
          },
          {
            "Comment" : "Successful Member -> LAG",
            "Condition" : "{% $jobStatus = 'COMPLETED' and $sourceAccountNumber != $accountId and $substring($destinationBackupVaultArn, 0, $length($lagBackupVaultNamePrefix)) = $lagBackupVaultNamePrefix %}",
            "Assign" : {
              "sourceBackupVaultType" : "member",
            },
            "Next" : "GetDestinationRecoveryPointTags"
          }
        ],
        "Default" : "Succeed",
      },
      "StartCopyToStandardVault" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:startCopyJob",
        "Arguments" : {
          "DestinationBackupVaultArn" : "{% $standardBackupVaultArn %}",
          "IamRoleArn" : "{% $centralBackupServiceRoleArn %}",
          "RecoveryPointArn" : "{% $destinationRecoveryPointArn %}",
          "SourceBackupVaultName" : "{% $destinationBackupVaultName %}",
        },
        "Output" : "{% $states.input %}",
        "Next" : "GetDestinationRecoveryPointTags"
      },
      "GetDestinationRecoveryPointTags" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:listTags",
        "Arguments" : {
          "ResourceArn" : "{% $destinationRecoveryPointArn %}"
        },
        "Output" : "{% $states.input %}",
        "Assign" : {
          "configuredDeleteAfterDays" : "{% $lookup($states.result.Tags, $lookup($retentionTags, $sourceBackupVaultType)) %}"
        },
        "Credentials" : {
            "RoleArn" : "{% $sourceAccountNumber != $accountId ? $memberBackupOrchestrationRoleArn : null %}"
        },
        "Next" : "UpdateSourceRecoveryPointLifecycle"
      },
      "UpdateSourceRecoveryPointLifecycle" : {
        "Type" : "Choice",
        "Choices" : [
          {
            "Comment" : "",
            "Condition" : "{% $sourceBackupVaultType = 'member' %}",
            "Next" : "UpdateSourceRecoveryPointLifecycleMemberAccount"
          },
          {
            "Comment" : "",
            "Condition" : "{% $sourceBackupVaultType = 'intermediate' %}",
            "Next" : "UpdateSourceRecoveryPointLifecycleCentralAccount"
          }
        ],
        "Default" : "Succeed"
      },
      "UpdateSourceRecoveryPointLifecycleMemberAccount" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:updateRecoveryPointLifecycle",
        "Credentials" : { "RoleArn" : "{% $sourceBackupVaultType = 'member' ? $sourceAccountBackupServiceRoleArn : $centralBackupServiceRoleArn %}" },
        "Arguments" : {
          "BackupVaultName" : "{% $sourceBackupVaultName %}",
          "RecoveryPointArn" : "{% $sourceRecoveryPointArn %}",
          "Lifecycle" : {
            "DeleteAfterDays" : "{% $number($configuredDeleteAfterDays) %}"
          }
        },
        "Output" : "{% $states.input %}",
        "Next" : "Succeed"
      },
      "UpdateSourceRecoveryPointLifecycleCentralAccount" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:updateRecoveryPointLifecycle",
        "Arguments" : {
          "BackupVaultName" : "{% $sourceBackupVaultName %}",
          "RecoveryPointArn" : "{% $sourceRecoveryPointArn %}",
          "Lifecycle" : {
            "DeleteAfterDays" : "{% $number($configuredDeleteAfterDays) %}"
          }
        },
        "Output" : "{% $states.input %}",
        "Next" : "Succeed"
      },
      "Succeed" : {
        "Type" : "Succeed"
      }
    },
  })
}

#
# EventBridge Rule to trigger the Step Function
#
module "backup_ingest_eventbridge_role" {
  source = "../iam-role"

  name = "${local.backup_ingest_sfn_name}-eventbridge"
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
            "aws:SourceAccount" : local.account_id
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
        Resource : aws_sfn_state_machine.backup_ingest.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "backup_ingest" {
  name           = local.backup_ingest_sfn_name
  event_bus_name = aws_cloudwatch_event_bus.event_bus.name
  description    = "Triggers the ${aws_sfn_state_machine.backup_ingest.name} Step Function on backup copy job to/from specific vaults."

  event_pattern = jsonencode({
    "source" : ["aws.backup"],
    "detail-type" : ["Copy Job State Change"],
    "detail" : {
      "state" : ["COMPLETED"],
      "$or" : [
        {
          # Member -> Intermediate
          "sourceBackupVaultArn" : [{ "wildcard" : "arn:*:backup:*:*:backup-vault:${local.member_account_backup_vault_name}" }],
          "destinationBackupVaultArn" : [aws_backup_vault.intermediate.arn]
        },
        {
          # Intermediate -> Standard
          "sourceBackupVaultArn" : [aws_backup_vault.intermediate.arn],
          "destinationBackupVaultArn" : values(aws_backup_vault.standard)[*].arn
        },
        {
          # Member -> LAG
          "sourceBackupVaultArn" : [{ "wildcard" : "arn:*:backup:*:*:backup-vault:${local.member_account_backup_vault_name}" }],
          "destinationBackupVaultArn" : concat([1], values(aws_backup_logically_air_gapped_vault.lag)[*].arn)
        }
      ]

    }
  })
}

resource "aws_cloudwatch_event_target" "backup_ingest" {
  arn            = aws_sfn_state_machine.backup_ingest.arn
  event_bus_name = aws_cloudwatch_event_rule.backup_ingest.event_bus_name
  role_arn       = module.backup_ingest_eventbridge_role.role.arn
  rule           = aws_cloudwatch_event_rule.backup_ingest.name
}
