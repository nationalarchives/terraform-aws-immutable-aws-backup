#
# Role for the EventBridge Rule to trigger the Backup Ingest Step Function
#
module "backup_ingest_eventbridge_role" {
  source = "../iam-role"

  name = "${local.ingest_state_machine_name}-eventbridge"
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
            "aws:SourceAccount" : var.current.account_id
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
        Resource : [for i in var.deployment_regions : "arn:${var.current.partition}:states:${i}:${var.current.account_id}:stateMachine:${local.ingest_state_machine_name}"]
      }
    ]
  })
}

#
# Role for the Backup Ingest Step Function to assume
#
module "backup_ingest_sfn_role" {
  source = "../iam-role"

  name = "${local.ingest_state_machine_name}-sfn"
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
            "aws:SourceAccount" : var.current.account_id
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
        "Resource" : flatten([
          [for i in var.deployment_regions : replace(local.current_standard_vault_arn_template, "<REGION>", i)],
          [for i in var.deployment_regions : replace(local.intermediate_vault_arn_template, "<REGION>", i)],
        ])
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

#
# IAM Role for the Backup Ingest Step Function to assume within states
# This is required to prevent a self-assuming role which could enable persistence.
#
module "backup_ingest_sfn_state_role" {
  source = "../iam-role"

  name = "${local.ingest_state_machine_name}-sfn-states"
  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Principal : {
          AWS : module.backup_ingest_sfn_role.role.arn
        },
        Action : "sts:AssumeRole"
      }
    ]
  })
  inline_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        "Sid" : "AllowGetTags",
        "Effect" : "Allow",
        "Action" : [
          "backup:ListTags",
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
        Effect : "Allow",
        Action : [
          "backup:UpdateRecoveryPointLifecycle"
        ],
        Resource : "*"
      }
    ]
  })
}
