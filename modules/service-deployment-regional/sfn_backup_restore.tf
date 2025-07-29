#
# Step Function to copy backups to member account restore vaults (...-default)
#
resource "aws_cloudwatch_log_group" "backup_restore" {
  region            = var.region
  name              = "/aws/vendedlogs/states/${var.stepfunctions.restore_state_machine_name}"
  retention_in_days = 90
}

resource "aws_sfn_state_machine" "backup_restore" {
  name     = var.stepfunctions.restore_state_machine_name
  role_arn = var.stepfunctions.restore_state_machine_role_arn

  logging_configuration {
    level                  = "ALL"
    include_execution_data = true
    log_destination        = "${aws_cloudwatch_log_group.backup_restore.arn}:*"
  }

  /*
  Step Function input:
  {
    "destinationAccount": "222222222222",
    "recoveryPointArn": "arn:aws:backup:eu-west-2:111111111111:recovery-point:website-logs-20250708044140-61ebc5da",
    "sourceBackupVaultName": "central-account-backup-vault"
  }
  */
  definition = jsonencode({
    "QueryLanguage" : "JSONata"
    "StartAt" : "SetVars",
    "States" : {
      "SetVars" : {
        "Type" : "Pass",
        "Assign" : {
          "accountId" : var.current.account_id,
          "backupVaultArnPrefix" : "arn:${var.current.partition}:backup:${var.current.region}:<accountId>:backup-vault:",
          "centralBackupServiceRoleArn" : var.deployment.backup_service_role_arn,
          "iamRoleArnPrefix" : "arn:${var.current.partition}:iam::<accountId>:role/",
          "intermediateBackupVaultArn" : aws_backup_vault.intermediate.arn,
          "memberAccountBackupServiceRoleName" : var.deployment.member_account_backup_service_role_name,
          "memberAccountBackupVaultName" : var.deployment.member_account_backup_vault_name,
          "memberAccountRestoreVaultName" : var.deployment.member_account_restore_vault_name,
          "standardBackupVaultArns" : values(aws_backup_vault.standard)[*].arn,
          "waitSeconds" : 30
        },
        "Output" : "{% $states.input %}"
        "Next" : "SourceVault?"
      }
      "SourceVault?" : {
        "Type" : "Choice",
        "Choices" : [
          {
            "Condition" : "{% ($replace($backupVaultArnPrefix, '<accountId>', $accountId) & $states.input.sourceBackupVaultName) in $standardBackupVaultArns %}",
            "Next" : "StartCopyToIntermediateVault"
          },
          {
            "Condition" : "{% ($replace($backupVaultArnPrefix, '<accountId>', $accountId) & $states.input.sourceBackupVaultName) = $intermediateBackupVaultArn %}",
            "Next" : "StartCopyToDestinationAccountBackupVault"
          }
        ]
      },
      # Copy Standard -> Intermediate vault
      "StartCopyToIntermediateVault" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:startCopyJob",
        "Arguments" : {
          "DestinationBackupVaultArn" : "{% $intermediateBackupVaultArn %}",
          "IamRoleArn" : "{% $centralBackupServiceRoleArn %}",
          "RecoveryPointArn" : "{% $states.input.recoveryPointArn %}",
          "SourceBackupVaultName" : "{% $states.input.sourceBackupVaultName %}",
        },
        "Output" : "{% $merge([$states.input, $states.result ]) %}",
        "Next" : "WaitForCopyToIntermediateVault"
      },
      "WaitForCopyToIntermediateVault" : {
        "Type" : "Wait",
        "Seconds" : "{% $waitSeconds %}",
        "Next" : "DescribeCopyToIntermediateVault"
      }
      "DescribeCopyToIntermediateVault" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:describeCopyJob",
        "Arguments" : {
          "CopyJobId" : "{% $states.input.CopyJobId %}"
        },
        "Output" : "{% $merge([$states.input, $states.result ]) %}",
        "Next" : "CopiedToIntermediateVault?"
      },
      "CopiedToIntermediateVault?" : {
        "Type" : "Choice",
        "Choices" : [
          {
            "Condition" : "{% $states.input.CopyJob.State = 'COMPLETED' %}",
            "Next" : "StartCopyToDestinationAccountBackupVault"
          },
          {
            "Condition" : "{% $states.input.CopyJob.State in ['CREATED', 'RUNNING'] %}",
            "Next" : "WaitForCopyToIntermediateVault"
          }
        ],
        "Default" : "Fail"
      },
      # Copy Intermediate -> Destination Account Backup vault
      "StartCopyToDestinationAccountBackupVault" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:startCopyJob",
        "Arguments" : {
          "DestinationBackupVaultArn" : "{% $replace($backupVaultArnPrefix, '<accountId>', $states.input.destinationAccount) & $memberAccountBackupVaultName %}",
          "IamRoleArn" : "{% $centralBackupServiceRoleArn %}",
          "RecoveryPointArn" : "{% $states.input.CopyJob ? $states.input.CopyJob.DestinationRecoveryPointArn : $states.input.recoveryPointArn %}",
          "SourceBackupVaultName" : "{% $match($intermediateBackupVaultArn, /backup-vault:([^:]*)/).groups[0] %}",
        },
        "Output" : "{% $merge([$states.input, $states.result ]) %}",
        "Next" : "WaitForCopyToDestinationAccountBackupVault"
      },
      "WaitForCopyToDestinationAccountBackupVault" : {
        "Type" : "Wait",
        "Seconds" : "{% $waitSeconds %}",
        "Next" : "DescribeCopyToDestinationAccountBackupVault"
      }
      "DescribeCopyToDestinationAccountBackupVault" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:describeCopyJob",
        "Arguments" : {
          "CopyJobId" : "{% $states.input.CopyJobId %}"
        },
        "Output" : "{% $merge([$states.input, $states.result ]) %}",
        "Next" : "CopiedToDestinationAccountBackupVault?"
      },
      "CopiedToDestinationAccountBackupVault?" : {
        "Type" : "Choice",
        "Choices" : [
          {
            "Condition" : "{% $states.input.CopyJob.State = 'COMPLETED' %}",
            "Next" : "StartCopyToDestinationAccountRestoreVault"
          },
          {
            "Condition" : "{% $states.input.CopyJob.State in ['CREATED', 'RUNNING'] %}",
            "Next" : "WaitForCopyToDestinationAccountBackupVault"
          }
        ],
        "Default" : "Fail"
      },
      # Copy Destination Account Backup vault -> Destination Account Restore vault
      "StartCopyToDestinationAccountRestoreVault" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:startCopyJob",
        "Credentials" : { "RoleArn" : "{% $replace($iamRoleArnPrefix, '<accountId>', $states.input.destinationAccount) & $memberAccountBackupServiceRoleName %}" },
        "Arguments" : {
          "DestinationBackupVaultArn" : "{% $replace($backupVaultArnPrefix, '<accountId>', $states.input.destinationAccount) & $memberAccountRestoreVaultName %}",
          "IamRoleArn" : "{% $replace($iamRoleArnPrefix, '<accountId>', $states.input.destinationAccount) & $memberAccountBackupServiceRoleName  %}",
          "RecoveryPointArn" : "{% $states.input.CopyJob ? $states.input.CopyJob.DestinationRecoveryPointArn : $states.input.recoveryPointArn %}",
          "SourceBackupVaultName" : "{% $memberAccountBackupVaultName %}",
        },
        "Output" : "{% $merge([$states.input, $states.result ]) %}",
        "Next" : "WaitForCopyToDestinationAccountRestoreVault"
      },
      "WaitForCopyToDestinationAccountRestoreVault" : {
        "Type" : "Wait",
        "Seconds" : "{% $waitSeconds %}",
        "Next" : "DescribeCopyToDestinationAccountRestoreVault"
      }
      "DescribeCopyToDestinationAccountRestoreVault" : {
        "Type" : "Task",
        "Resource" : "arn:aws:states:::aws-sdk:backup:describeCopyJob",
        "Arguments" : {
          "CopyJobId" : "{% $states.input.CopyJobId %}"
        },
        "Output" : "{% $merge([$states.input, $states.result ]) %}",
        "Next" : "CopiedToDestinationAccountRestoreVault?"
      },
      "CopiedToDestinationAccountRestoreVault?" : {
        "Type" : "Choice",
        "Choices" : [
          {
            "Condition" : "{% $states.input.CopyJob.State = 'COMPLETED' %}",
            "Next" : "Succeed"
          },
          {
            "Condition" : "{% $states.input.CopyJob.State in ['CREATED', 'RUNNING'] %}",
            "Next" : "WaitForCopyToDestinationAccountRestoreVault"
          }
        ],
        "Default" : "Fail"
      },
      "Succeed" : {
        "Type" : "Succeed"
      },
      "Fail" : {
        "Type" : "Fail",
      },
    }
  })
}
