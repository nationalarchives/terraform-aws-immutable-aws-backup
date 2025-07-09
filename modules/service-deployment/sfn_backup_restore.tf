locals {
  backup_restore_sfn_name = "${local.central_account_resource_name_prefix}-backup-restore"

  backup_restore_sfn_vault_to_next_vault = merge(
    { for i in aws_backup_vault.standard : i.name => [aws_backup_vault.intermediate.arn, aws_backup_vault.intermediate.name] },
    { (aws_backup_vault.intermediate.name) : ["arn:${local.partition_id}:${local.region}:<accountNumber>:backup-vault:${local.member_account_backup_vault_name}", local.member_account_backup_vault_name] },
    { (local.member_account_backup_vault_name) : ["arn:${local.partition_id}:${local.region}:<accountNumber>:backup-vault:${local.member_account_restore_vault_name}", local.member_account_restore_vault_name] }
  )
}

#
# Step Function to copy backups from the standard vault back to member accounts (default vault)
#
module "backup_restore_sfn_role" {
  source = "../iam-role"

  name = "${local.backup_restore_sfn_name}-sfn"
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
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "backup_restore" {
  name              = "/aws/vendedlogs/states/${local.backup_restore_sfn_name}"
  retention_in_days = 90
}

resource "aws_sfn_state_machine" "backup_restore" {
  name = local.backup_restore_sfn_name
  #TODO: Fix this
  # role_arn = module.backup_restore_sfn_role.role.arn
  role_arn = module.backup_ingest_sfn_role.role.arn

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
          "accountId" : local.account_id,
          "backupVaultArnPrefix" : "arn:${local.partition_id}:backup:${local.region}:<accountId>:backup-vault:",
          "centralBackupServiceRoleArn" : module.backup_service_role.role.arn,
          "iamRoleArnPrefix" : "arn:${local.partition_id}:iam::<accountId>:role/",
          "intermediateBackupVaultArn" : aws_backup_vault.intermediate.arn,
          "memberAccountBackupServiceRoleName" : local.member_account_backup_service_role_name,
          "memberAccountBackupVaultName" : local.member_account_backup_vault_name,
          "memberAccountRestoreVaultName" : local.member_account_restore_vault_name,
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
        "Credentials" : { "RoleArn" : "{% $replace($iamRoleArnPrefix, '<accountNumber>', $states.input.destinationAccount) & $memberAccountBackupServiceRoleName %}" },
        "Arguments" : {
          "DestinationBackupVaultArn" : "{% $replace($iamRoleArnPrefix, '<accountNumber>', $states.input.destinationAccount) & $memberAccountBackupServiceRoleName %}",
          "IamRoleArn" : "{% 'arn:' & $partition & ':iam::' & $states.input.destinationAccount & ':role/' & $memberAccountBackupServiceRoleName %}",
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
