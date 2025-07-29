locals {
  local_retention_days_tag        = "BackupLocalRetentionDays"
  intermediate_retention_days_tag = "BackupIntermediateRetentionDays"

  central_account_resource_name_prefix = "${var.central_account_resource_name_prefix}${var.service_name}"
  event_bus_name                       = local.central_account_resource_name_prefix
  ingest_state_machine_name            = join("", [local.central_account_resource_name_prefix, "-backup-ingest"])
  restore_state_machine_name           = join("", [local.central_account_resource_name_prefix, "-backup-restore"])
  lag_share_name                       = local.central_account_resource_name_prefix

  member_account_resource_name_prefix     = join("", [var.member_account_resource_name_prefix, var.service_name])
  member_account_backup_vault_name        = join("", [local.member_account_resource_name_prefix, "-cmk"])
  member_account_restore_vault_name       = join("", [local.member_account_resource_name_prefix, "-default"])
  member_account_backup_service_role_name = join("", [local.member_account_resource_name_prefix, "-backup-service-role"])
  member_account_eventbridge_rule_name    = join("", [local.member_account_resource_name_prefix, "-event-forwarder"])

  # Use different prefix so any SCP restrictions don't apply to restore role
  member_account_backup_service_restore_role_name = join("", [local.central_account_resource_name_prefix, "-backup-service-restore-role"])

  create_lag_resources                   = anytrue(values(var.plans)[*]["use_logically_air_gapped_vault"]) ? true : false
  lag_vaults_exist                       = anytrue(flatten([local.create_lag_resources, var.retained_vaults[*].use_logically_air_gapped_vault]))
  create_lag_shares                      = var.restores_enabled && local.lag_vaults_exist ? true : false
  deployment_ou_paths_including_children = [for i in var.deployment_targets : "${var.current.organization_id}/*/${i}/*"]

  # Backup Vaults
  current_vault_configuration              = join("-", [coalesce(var.min_retention_days, "0"), coalesce(var.max_retention_days, "0")])
  intermediate_vault_name                  = "${local.central_account_resource_name_prefix}-intermediate"
  lag_vault_prefix                         = "${local.central_account_resource_name_prefix}-lag-"
  lag_vaults                               = concat([for i in var.retained_vaults : "${i.min_retention_days}-${i.max_retention_days}" if i["use_logically_air_gapped_vault"]], local.create_lag_resources ? [local.current_vault_configuration] : [])
  standard_vault_prefix                    = "${local.central_account_resource_name_prefix}-standard-"
  standard_vaults                          = concat([for i in var.retained_vaults : "${i.min_retention_days}-${i.max_retention_days}"], [local.current_vault_configuration])
  central_backup_vault_arn_prefix_template = "arn:${var.current.partition}:backup:<REGION>:${var.current.account_id}:backup-vault:"
  intermediate_vault_arn_template          = join("", [local.central_backup_vault_arn_prefix_template, local.intermediate_vault_name])
  current_lag_vault_arn_template           = join("", [local.central_backup_vault_arn_prefix_template, local.lag_vault_prefix, local.current_vault_configuration])
  current_standard_vault_arn_template      = join("", [local.central_backup_vault_arn_prefix_template, local.standard_vault_prefix, local.current_vault_configuration])
  central_backup_vault_arns_template = flatten([
    join("", [local.central_backup_vault_arn_prefix_template, local.intermediate_vault_name]),
    [for i in local.standard_vaults : join("", [local.central_backup_vault_arn_prefix_template, local.standard_vault_prefix, i])],
    [for i in local.lag_vaults : join("", [local.central_backup_vault_arn_prefix_template, local.lag_vault_prefix, i])]
  ])


  #
  # Base policy statements for Step Function Roles
  #
  step_function_role_policy_statements = [
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
      "Sid" : "AllowPassRole",
      "Effect" : "Allow",
      "Action" : [
        "iam:PassRole"
      ],
      "Resource" : module.backup_service_role.role.arn
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
}
