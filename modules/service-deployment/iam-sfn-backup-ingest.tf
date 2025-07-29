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
    Statement : local.step_function_role_policy_statements
    # Can assume the backup_ingest_sfn_state_role through same-account trust policy
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
