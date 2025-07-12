resource "aws_ram_resource_share" "backup_vaults" {
  count = var.ram.create_lag_shares ? 1 : 0

  region                    = var.region
  name                      = var.ram.lag_share_name
  allow_external_principals = false
}

resource "aws_ram_resource_association" "backup_vaults" {
  for_each = var.ram.create_lag_shares ? aws_backup_logically_air_gapped_vault.lag : {}

  region             = var.region
  resource_share_arn = aws_ram_resource_share.backup_vaults[0].arn
  resource_arn       = each.value.arn
}

resource "aws_ram_principal_association" "backup_vaults" {
  for_each = toset(var.ram.target_account_ids) # [] if var.ram.create_lag_shares is false

  region             = var.region
  resource_share_arn = aws_ram_resource_share.backup_vaults[0].arn
  principal          = each.key
}
