#
# Creates a service role for AWS Backup.
#

module "backup_service_role" {
  source = "./modules/iam-role"

  name = join("", [var.central_account_resource_name_prefix, "backup-service-role"])
  assume_role_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Effect = "Allow",
        Principal : {
          Service : "backup.amazonaws.com"
        },
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
        Sid : "BackupVaultPermissions",
        Effect : "Allow",
        Action : [
          "backup:DescribeBackupVault",
          "backup:CopyIntoBackupVault"
        ],
        Resource : "arn:aws:backup:*:*:backup-vault:*"
      },
      {
        Sid : "BackupVaultCopyPermissions",
        Effect : "Allow",
        Action : [
          "backup:CopyFromBackupVault"
        ],
        Resource : "*"
      },
      {
        Sid : "RecoveryPointTaggingPermissions",
        Effect : "Allow",
        Action : [
          "backup:TagResource"
        ],
        Resource : "arn:aws:backup:*:*:recovery-point:*",
        Condition : {
          StringEquals : {
            "aws:PrincipalAccount" : "$${aws:ResourceAccount}"
          }
        }
      },
      {
        Sid : "KMSPermissions",
        Effect : "Allow",
        Action : "kms:DescribeKey",
        Resource : "*"
      },
      {
        Sid : "KMSCreateGrantPermissions",
        Effect : "Allow",
        Action : "kms:CreateGrant",
        Resource : "*",
        Condition : {
          Bool : {
            "kms:GrantIsForAWSResource" : "true"
          }
        }
      }
    ]
  })
}
