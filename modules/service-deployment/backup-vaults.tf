locals {
  standard_vault_prefix = "${local.central_account_resource_name_prefix}-standard-"
  lag_vault_prefix      = "${local.central_account_resource_name_prefix}-lag-"

  current_vault_configuration = join("-", [coalesce(var.min_retention_days, "0"), coalesce(var.max_retention_days, "0")])
  standard_vaults             = concat([for i in var.retained_vaults : "${i.min_retention_days}-${i.max_retention_days}"], [local.current_vault_configuration])
  lag_vaults                  = concat([for i in var.retained_vaults : "${i.min_retention_days}-${i.max_retention_days}" if i["use_logically_air_gapped_vault"]], local.create_lag_resources ? [local.current_vault_configuration] : [])

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
            "aws:PrincipalArn" : "arn:*:iam::*:role/${local.member_account_backup_service_role_name}"
          },
          "ForAnyValue:StringLike" : {
            "aws:PrincipalOrgPaths" : local.deployment_ou_paths_including_children
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
  name          = "${local.central_account_resource_name_prefix}-intermediate"
  kms_key_arn   = aws_kms_key.key.arn
  force_destroy = true
}
resource "aws_backup_vault_policy" "intermediate" {
  backup_vault_name = aws_backup_vault.intermediate.id
  policy            = local.copy_destination_vault_policy
}

#
# Logically Air Gapped Vault
#
resource "aws_backup_logically_air_gapped_vault" "lag" {
  for_each           = toset(local.lag_vaults)
  name               = join("", [local.lag_vault_prefix, each.key])
  min_retention_days = split("-", each.key)[0]
  max_retention_days = split("-", each.key)[1]
}

resource "aws_backup_vault_policy" "lag" {
  for_each          = toset(local.lag_vaults)
  backup_vault_name = aws_backup_logically_air_gapped_vault.lag[each.key].id
  policy            = local.copy_destination_vault_policy
}

#
# Standard Vault
#
resource "aws_backup_vault" "standard" {
  for_each      = toset(local.standard_vaults)
  name          = join("", [local.standard_vault_prefix, each.key])
  kms_key_arn   = null # Uses AWS Managed Key
  force_destroy = true
}

resource "aws_backup_vault_lock_configuration" "standard" {
  for_each          = toset(local.standard_vaults)
  backup_vault_name = aws_backup_vault.standard[each.key].name
  # changeable_for_days = 14
  changeable_for_days = var.use_governance_lock_mode ? null : var.compliance_lock_changeable_days
  max_retention_days  = split("-", each.key)[1]
  min_retention_days  = split("-", each.key)[0]
}

#
# Helpers to make it easier to reference the current vaults
#
locals {
  current_standard_vault = aws_backup_vault.standard[local.current_vault_configuration]
  current_lag_vault      = local.create_lag_resources ? aws_backup_logically_air_gapped_vault.lag[local.current_vault_configuration] : null
}