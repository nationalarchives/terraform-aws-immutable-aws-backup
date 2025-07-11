resource "aws_kms_key" "key" {
  description         = "Key for ${var.service_name} backups. Used to encrypt the member account vaults and the central intermediate vault."
  enable_key_rotation = true
  policy = jsonencode({
    Version : "2012-10-17"
    Statement : concat([
      {
        Sid : "DelegateToIamForOwnerAccount",
        Effect : "Allow",
        Principal : {
          AWS : "arn:${local.partition_id}:iam::${local.account_id}:root"
        },
        Action : "kms:*",
        Resource : "*"
      },
      {
        Sid : "AllowReadForMemberAccounts",
        Principal : {
          "AWS" : "*"
        },
        Effect : "Allow",
        Action : [
          "kms:Describe*",
          "kms:Get*",
          "kms:List*"
        ],
        Resource : "*",
        Condition : {
          "ForAnyValue:StringLike" : {
            "aws:PrincipalOrgPaths" : local.deployment_ou_paths_including_children
          }
        }
      },
      {
        Sid : "AllowUseForMemberAccounts",
        Principal : {
          AWS : "*"
        },
        Effect : "Allow",
        Action : [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:Encrypt",
          "kms:ReEncrypt*"
        ],
        Resource : "*",
        Condition : {
          ArnLike : {
            "aws:PrincipalArn" : [
              "arn:${local.partition_id}:iam::*:role/aws-service-role/backup.amazonaws.com/AWSServiceRoleForBackup",
              "arn:${local.partition_id}:iam::*:role/${local.member_account_backup_service_role_name}",
              "arn:${local.partition_id}:iam::*:role/${local.member_account_deployment_helper_role_name}"
            ]
          },
          "ForAnyValue:StringLike" : {
            "aws:PrincipalOrgPaths" : local.deployment_ou_paths_including_children
          }
        }
      },
      {
        Sid : "AllowUseForMemberAccounts",
        Principal : {
          AWS : "*"
        },
        Effect : "Allow",
        Action : [
          "kms:CreateGrant",
          "kms:RetireGrant",
          "kms:RevokeGrant"
        ],
        Resource : "*",
        Condition : {
          ArnLike : {
            "aws:PrincipalArn" : [
              "arn:${local.partition_id}:iam::*:role/aws-service-role/backup.amazonaws.com/AWSServiceRoleForBackup",
              "arn:${local.partition_id}:iam::*:role/${local.member_account_backup_service_role_name}",
              "arn:${local.partition_id}:iam::*:role/${local.member_account_deployment_helper_role_name}"
            ]
          },
          Bool : {
            "kms:GrantIsForAWSResource" : "true"
          },
          "ForAnyValue:StringLike" : {
            "aws:PrincipalOrgPaths" : local.deployment_ou_paths_including_children,
            "kms:ViaService" : "backup.*.amazonaws.com"
          }
        }
      }
      ],
      var.additional_kms_statements
    )
  })
}

resource "aws_kms_alias" "key" {
  name          = "alias/${local.central_account_resource_name_prefix}"
  target_key_id = aws_kms_key.key.key_id
}
