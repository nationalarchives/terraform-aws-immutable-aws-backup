resource "aws_cloudformation_stack_set" "member_account_deployments" {
  name             = local.member_account_resource_name_prefix
  description      = "Centralised AWS Backup for ${var.service_name}."
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  permission_model = "SERVICE_MANAGED"
  call_as          = "DELEGATED_ADMIN"
  template_body    = file("${path.module}/templates/stackset.cfn.json")

  parameters = {
    BackupServiceLinkedRoleArn  = var.central_backup_service_linked_role_arn
    BackupServiceRoleName       = local.member_account_backup_service_role_name
    BackupServiceRolePrincipals = join(", ", [module.backup_ingest_sfn_role.role.arn])
    BackupVaultName             = local.member_account_backup_vault_name
    CentralBackupVaultArns      = join(", ", local.central_backup_vault_arns)
    CentralEventBusArn          = aws_cloudwatch_event_bus.event_bus.arn
    DeploymentHelperRoleArn     = var.central_deployment_helper_role_arn
    DeploymentHelperRoleName    = local.member_account_deployment_helper_role_name
    DeploymentHelperTopicArn    = var.central_deployment_helper_topic_arn
    EventBridgeRuleName         = local.member_account_eventbridge_rule_name
    ForceDeployment             = "1"
    KmsKeyArn                   = aws_kms_key.key.arn
    OrganizationId              = local.organization_id
    RestoreVaultName            = local.member_account_restore_vault_name
  }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  operation_preferences {
    failure_tolerance_percentage = 10
    max_concurrent_percentage    = 100
    region_concurrency_type      = "PARALLEL"
  }

  lifecycle {
    ignore_changes = [administration_role_arn]
  }
}

resource "aws_cloudformation_stack_instances" "member_account_deployments" {
  stack_set_name = aws_cloudformation_stack_set.member_account_deployments.name
  call_as        = "DELEGATED_ADMIN"
  regions        = [data.aws_region.current.id]
  deployment_targets {
    organizational_unit_ids = var.deployment_targets
  }
}
