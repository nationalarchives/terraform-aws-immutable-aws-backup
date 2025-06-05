resource "aws_ram_resource_share" "backup_vaults" {
  count                     = local.create_lag_shares ? 1 : 0
  name                      = local.central_account_resource_name_prefix
  allow_external_principals = false
}

resource "aws_ram_resource_association" "backup_vaults" {
  for_each           = local.create_lag_shares ? aws_backup_logically_air_gapped_vault.lag : {}
  resource_share_arn = aws_ram_resource_share.backup_vaults[0].arn
  resource_arn       = each.value.arn
}

# AWS RAM for AWS Backup only supports sharing using account numbers.
data "aws_organizations_organizational_unit_descendant_accounts" "target_accounts" {
  for_each  = local.create_lag_shares ? toset(var.deployment_targets) : toset([])
  parent_id = each.key
}

resource "aws_ram_principal_association" "backup_vaults" {
  for_each           = local.create_lag_shares ? toset(flatten(values(data.aws_organizations_organizational_unit_descendant_accounts.target_accounts)[*].accounts[*].id)) : toset([])
  resource_share_arn = aws_ram_resource_share.backup_vaults[0].arn
  principal          = each.key
}
