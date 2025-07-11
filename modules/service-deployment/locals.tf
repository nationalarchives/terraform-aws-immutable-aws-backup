locals {
  local_retention_days_tag        = "BackupLocalRetentionDays"
  intermediate_retention_days_tag = "BackupIntermediateRetentionDays"
  account_id                      = data.aws_caller_identity.current.account_id
  organization_id                 = data.aws_organizations_organization.current.id
  partition_id                    = data.aws_partition.current.partition
  region                          = data.aws_region.current.region

  ingest_state_machine_name = join("", [var.central_account_resource_name_prefix, "-backup-ingest"])

  central_account_resource_name_prefix = "${var.central_account_resource_name_prefix}${var.service_name}"
  event_bus_name                       = local.central_account_resource_name_prefix
  lag_share_name                       = local.central_account_resource_name_prefix

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

  # Backup Vaults
  current_vault_configuration                = join("-", [coalesce(var.min_retention_days, "0"), coalesce(var.max_retention_days, "0")])
  intermediate_vault_name                    = "${local.central_account_resource_name_prefix}-intermediate"
  lag_vault_prefix                           = "${local.central_account_resource_name_prefix}-lag-"
  lag_vaults                                 = concat([for i in var.retained_vaults : "${i.min_retention_days}-${i.max_retention_days}" if i["use_logically_air_gapped_vault"]], local.create_lag_resources ? [local.current_vault_configuration] : [])
  standard_vault_prefix                      = "${local.central_account_resource_name_prefix}-standard-"
  standard_vaults                            = concat([for i in var.retained_vaults : "${i.min_retention_days}-${i.max_retention_days}"], [local.current_vault_configuration])
  central_backup_vault_arn_prefix_template   = "arn:${local.partition_id}:backup:<REGION>:${local.account_id}:backup-vault:"
  intermediate_vault_arn_template            = join("", [local.central_backup_vault_arn_prefix_template, local.intermediate_vault_name])
  current_lag_vault_arn_template             = join("", [local.central_backup_vault_arn_prefix_template, local.lag_vault_prefix, local.current_vault_configuration])
  current_standard_vault_arn_template        = join("", [local.central_backup_vault_arn_prefix_template, local.standard_vault_prefix, local.current_vault_configuration])
  central_backup_vault_regionless_arn_prefix = replace(local.central_backup_vault_arn_prefix_template, "<REGION>", "*")
  central_backup_vault_regionless_arns = flatten([
    join("", [local.central_backup_vault_regionless_arn_prefix, local.intermediate_vault_name]),
    [for i in local.standard_vaults : join("", [local.central_backup_vault_regionless_arn_prefix, local.standard_vault_prefix, i])],
    [for i in local.lag_vaults : join("", [local.central_backup_vault_regionless_arn_prefix, local.lag_vault_prefix, i])]
  ])

}
