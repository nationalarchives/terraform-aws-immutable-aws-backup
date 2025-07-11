locals {
  copy_destination_vault_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Sid : "AllowCopyIntoVaultFromMemberVaults",
        Effect : "Allow",
        Principal : {
          AWS : "*"
        },
        Action : "backup:CopyIntoBackupVault",
        Resource : "*",
        Condition : {
          ArnLike : {
            "aws:PrincipalArn" : "arn:${var.current_aws_partition}:iam::*:role/${var.member_account_backup_service_role_name}"
          },
          "ForAnyValue:StringLike" : {
            "aws:PrincipalOrgPaths" : var.deployment.ou_paths_including_children
          }
        }
      }
    ]
  })

}

#
# Intermediate Vault
#
resource "aws_backup_vault" "intermediate" {
  region        = var.region
  name          = var.backup_vaults.intermediate_vault_name
  kms_key_arn   = local.kms_key_arn
  force_destroy = true
}

resource "aws_backup_vault_policy" "intermediate" {
  region            = var.region
  backup_vault_name = aws_backup_vault.intermediate.id
  policy            = local.copy_destination_vault_policy
}

#
# Logically Air Gapped Vault
#
resource "aws_backup_logically_air_gapped_vault" "lag" {
  for_each = toset(var.backup_vaults.lag_vaults)

  region             = var.region
  name               = join("", [var.backup_vaults.lag_vault_prefix, each.key])
  min_retention_days = split("-", each.key)[0]
  max_retention_days = split("-", each.key)[1]
}

resource "aws_backup_vault_policy" "lag" {
  for_each = toset(var.backup_vaults.lag_vaults)

  region            = var.region
  backup_vault_name = aws_backup_logically_air_gapped_vault.lag[each.key].id
  policy            = local.copy_destination_vault_policy
}

#
# Standard Vault
#
resource "aws_backup_vault" "standard" {
  for_each = toset(var.backup_vaults.standard_vaults)

  region        = var.region
  name          = join("", [var.backup_vaults.standard_vault_prefix, each.key])
  kms_key_arn   = null # Uses AWS Managed Key
  force_destroy = true
}

resource "aws_backup_vault_lock_configuration" "standard" {
  for_each = toset(var.backup_vaults.standard_vaults)

  region            = var.region
  backup_vault_name = aws_backup_vault.standard[each.key].name
  # changeable_for_days = 14
  max_retention_days = split("-", each.key)[1]
  min_retention_days = split("-", each.key)[0]
}

#
# Helpers to make it easier to reference the current vaults
#
locals {
  current_standard_vault = aws_backup_vault.standard[var.backup_vaults.current_vault_configuration]
  current_lag_vault      = try(aws_backup_logically_air_gapped_vault.lag[var.backup_vaults.current_vault_configuration], null)
  central_backup_vault_arns = flatten([
    aws_backup_vault.intermediate.arn,
    values(aws_backup_vault.standard)[*].arn,
    values(aws_backup_logically_air_gapped_vault.lag)[*].arn
  ])
}
