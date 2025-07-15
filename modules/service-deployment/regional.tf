# AWS RAM for AWS Backup only supports sharing using account numbers.
data "aws_organizations_organizational_unit_descendant_accounts" "target_accounts" {
  for_each  = local.create_lag_shares ? toset(var.deployment_targets) : toset([])
  parent_id = each.key
}

#
# Module for deploying AWS Backup resources in a specific region.
#
module "region" {
  source   = "../service-deployment-regional"
  for_each = toset(var.deployment_regions)

  region                 = each.value
  current_aws_account_id = var.current.account_id
  current_aws_partition  = var.current.partition
  current_aws_region     = var.current.region

  member_account_backup_service_role_name = local.member_account_backup_service_role_name
  member_account_eventbridge_rule_name    = local.member_account_eventbridge_rule_name
  member_account_backup_vault_name        = local.member_account_backup_vault_name

  backup_policies = {
    intermediate_retention_days_tag = local.intermediate_retention_days_tag
    local_retention_days_tag        = local.local_retention_days_tag
  }
  backup_vaults = {
    current_vault_configuration = local.current_vault_configuration
    intermediate_vault_name     = local.intermediate_vault_name
    lag_vault_prefix            = local.lag_vault_prefix
    lag_vaults                  = local.lag_vaults
    standard_vault_prefix       = local.standard_vault_prefix
    standard_vaults             = local.standard_vaults
  }
  deployment = {
    backup_service_role_arn     = var.central_backup_service_role_arn
    ou_paths_including_children = local.deployment_ou_paths_including_children
  }
  eventbridge = {
    bus_name               = local.event_bus_name
    forwarder_iam_role_arn = module.default_to_event_bus_role.role.arn
  }
  kms = {
    kms_key_alias   = aws_kms_alias.key.name
    kms_key_id      = aws_kms_key.key.key_id
    kms_key_policy  = local.kms_key_policy
    primary_key_arn = aws_kms_key.key.arn
  }
  ram = {
    create_lag_shares  = local.create_lag_shares
    lag_share_name     = local.lag_share_name
    target_account_ids = try(flatten(values(data.aws_organizations_organizational_unit_descendant_accounts.target_accounts)[*].accounts[*].id), [])
  }
  stepfunctions = {
    ingest_state_machine_name          = local.ingest_state_machine_name
    ingest_state_machine_role_arn      = module.backup_ingest_sfn_role.role.arn
    ingest_eventbridge_target_role_arn = module.backup_ingest_eventbridge_role.role.arn
  }
}
