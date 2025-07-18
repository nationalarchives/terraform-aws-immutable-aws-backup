#
# EventBridge Rule to trigger the Backup Ingest Step Function
#
resource "aws_cloudwatch_event_rule" "backup_ingest" {
  region         = var.region
  name           = var.stepfunctions.ingest_state_machine_name
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
          "sourceBackupVaultArn" : [{ "wildcard" : "arn:*:backup:*:*:backup-vault:${var.member_account_backup_vault_name}" }],
          "destinationBackupVaultArn" : [aws_backup_vault.intermediate.arn]
        },
        {
          # Intermediate -> Standard
          "sourceBackupVaultArn" : [aws_backup_vault.intermediate.arn],
          "destinationBackupVaultArn" : values(aws_backup_vault.standard)[*].arn
        },
        {
          # Member -> LAG
          "sourceBackupVaultArn" : [{ "wildcard" : "arn:*:backup:*:*:backup-vault:${var.member_account_backup_vault_name}" }],
          "destinationBackupVaultArn" : concat([1], values(aws_backup_logically_air_gapped_vault.lag)[*].arn)
        }
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "backup_ingest" {
  region         = var.region
  arn            = aws_sfn_state_machine.backup_ingest.arn
  event_bus_name = aws_cloudwatch_event_rule.backup_ingest.event_bus_name
  role_arn       = var.stepfunctions.ingest_eventbridge_target_role_arn
  rule           = aws_cloudwatch_event_rule.backup_ingest.name
}

#
# Step Function to copy backups between vaults
#
resource "aws_cloudwatch_log_group" "backup_ingest" {
  region            = var.region
  name              = "/aws/vendedlogs/states/${var.stepfunctions.ingest_state_machine_name}"
  retention_in_days = 90
}

resource "aws_sfn_state_machine" "backup_ingest" {
  region   = var.region
  name     = var.stepfunctions.ingest_state_machine_name
  role_arn = var.stepfunctions.ingest_state_machine_role_arn
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
          "accountId" : var.current_aws_account_id,
          "backupIngestSfnStateRoleArn" : var.stepfunctions.ingest_state_role_arn,
          "centralBackupServiceRoleArn" : var.deployment.backup_service_role_arn,
          "destinationBackupVaultArn" : "{% $states.input.detail.destinationBackupVaultArn %}",
          "destinationRecoveryPointArn" : "{% $states.input.detail.destinationRecoveryPointArn %}",
          "intermediateBackupVaultArn" : aws_backup_vault.intermediate.arn,
          "jobStatus" : "{% $states.input.detail.state %}",
          "lagBackupVaultNamePrefix" : var.backup_vaults.lag_vault_prefix,
          "memberAccountBackupServiceRoleName" : var.member_account_backup_service_role_name,
          "partitionId" : var.current_aws_partition,
          "retentionTags" : {
            "member" : var.backup_policies.local_retention_days_tag,
            "intermediate" : var.backup_policies.intermediate_retention_days_tag,
          },
          "sourceAccountNumber" : "{% $states.input.account %}",
          "sourceBackupVaultArn" : "{% $states.input.detail.sourceBackupVaultArn %}",
          "sourceRecoveryPointArn" : "{% $states.input.resources[0] %}",
          "standardBackupVaultArn" : local.current_standard_vault.arn,
          "standardBackupVaultNamePrefix" : var.backup_vaults.standard_vault_prefix,
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
            "Next" : "GetSourceRecoveryPointTags"
          },
          {
            "Comment" : "Successful Member -> LAG",
            "Condition" : "{% $jobStatus = 'COMPLETED' and $sourceAccountNumber != $accountId and $substring($destinationBackupVaultName, 0, $length($lagBackupVaultNamePrefix)) = $lagBackupVaultNamePrefix %}",
            "Assign" : {
              "sourceBackupVaultType" : "member",
            },
            "Next" : "GetSourceRecoveryPointTags"
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
        "Next" : "GetSourceRecoveryPointTags"
      },
      "GetSourceRecoveryPointTags" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:listTags",
        "Credentials" : { "RoleArn" : "{% $sourceAccountNumber = $accountId ? $backupIngestSfnStateRoleArn : $sourceAccountBackupServiceRoleArn %}" },
        "Arguments" : {
          "ResourceArn" : "{% $sourceRecoveryPointArn %}"
        },
        "Output" : "{% $states.input %}",
        "Assign" : {
          "configuredDeleteAfterDays" : "{% $lookup($states.result.Tags, $lookup($retentionTags, $sourceBackupVaultType)) %}"
        },
        "Next" : "UpdateSourceRecoveryPointLifecycle"
      },
      "UpdateSourceRecoveryPointLifecycle" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:updateRecoveryPointLifecycle",
        "Credentials" : { "RoleArn" : "{% $sourceAccountNumber = $accountId ? $backupIngestSfnStateRoleArn : $sourceAccountBackupServiceRoleArn %}" },
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

