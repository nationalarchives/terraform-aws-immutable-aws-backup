locals {
  local_retention_days_tag        = "BackupLocalRetentionDays"
  intermediate_retention_days_tag = "BackupIntermediateRetentionDays"
  account_id                      = data.aws_caller_identity.current.account_id
  organization_id                 = data.aws_organizations_organization.current.id
  partition_id                    = data.aws_partition.current.partition

  central_account_resource_name_prefix = "${var.central_account_resource_name_prefix}${var.service_name}"

  member_account_resource_name_prefix        = join("", [var.member_account_resource_name_prefix, var.service_name])
  member_account_backup_vault_name           = join("", [local.member_account_resource_name_prefix, "-cmk"])
  member_account_restore_vault_name          = join("", [local.member_account_resource_name_prefix, "-default"])
  member_account_backup_service_role_name    = join("", [local.member_account_resource_name_prefix, "-backup-service-role"])
  member_account_eventbridge_rule_name       = join("", [local.member_account_resource_name_prefix, "-event-forwarder"])
  member_account_deployment_helper_role_name = join("", [local.member_account_resource_name_prefix, var.member_account_deployment_helper_role_name_suffix])

  create_lag_resources                   = anytrue(values(var.plans)[*]["use_logically_air_gapped_vault"]) ? true : false
  lag_vaults_exist                       = anytrue(flatten([local.create_lag_resources, var.retained_vaults[*].use_logically_air_gapped_vault]))
  create_lag_shares                      = var.restores_enabled && local.lag_vaults_exist ? true : false
  deployment_ou_paths_including_children = [for i in var.deployment_targets : "${data.aws_organizations_organization.current.id}/*/${i}/*"]
}
