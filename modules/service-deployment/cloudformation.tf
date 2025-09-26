locals {
  cfn_backup_vault_admin_arn_templates = flatten([
    { "Fn::GetAtt" : ["DeploymentHelperRole", "Arn"] },
    { "Fn::Sub" : "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/$${BackupServiceRoleName}" },
    [for i in var.admin_role_names : { "Fn::Sub" : "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:role/${i}" }],
    { "Ref" : "CentralBackupServiceRoleArn" }
  ])
  cfn_call_as = var.current.organization_management_account_id == var.current.account_id ? "SELF" : "DELEGATED_ADMIN"
}

resource "aws_cloudformation_stack_set" "member_account_deployments" {
  name             = local.member_account_resource_name_prefix
  description      = "Centralised AWS Backup for ${var.service_name}."
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  permission_model = "SERVICE_MANAGED"
  call_as          = local.cfn_call_as

  # Try to do as much as possible in native CloudFormation, but some things, like dynamic lists, are only possible in Terraform.
  # jsonencode(jsondecode(...)) used to minify the file.
  template_body = templatefile("${path.module}/templates/stackset.json.tftpl", {
    central_backup_vault_arn_templates    = [for i in local.central_backup_vault_arns_template : { "Fn::Sub" : replace(replace(i, "<REGION>", "$${AWS::Region}"), var.current.account_id, "$${CentralAccountId}") }],
    member_eventbridge_rule_arn_templates = [for i in var.deployment_regions : { "Fn::Sub" : "arn:${var.current.partition}:events:${i}:$${AWS::AccountId}:rule/${local.member_account_eventbridge_rule_name}" }],
    backup_vault_admin_arn_templates      = local.cfn_backup_vault_admin_arn_templates
  })

  parameters = {
    BackupServiceLinkedRoleArn     = var.central_backup_service_linked_role_arn
    BackupServiceRoleName          = local.member_account_backup_service_role_name
    BackupServiceRestoreRoleName   = local.member_account_backup_service_restore_role_name
    BackupServiceRolePrincipals    = join(", ", [module.backup_ingest_sfn_role.role.arn, module.backup_restore_sfn_role.role.arn])
    BackupVaultName                = local.member_account_backup_vault_name
    CentralAccountId               = var.current.account_id
    CentralBackupServiceRoleArn    = module.backup_service_role.role.arn
    DeploymentHelperRoleArn        = var.central_deployment_helper_role_arn
    DeploymentHelperRoleNamePrefix = replace(var.member_account_deployment_helper_role_name_template, "<REGION>", "")
    DeploymentHelperTopicName      = var.central_deployment_helper_topic_name
    EventBridgeRuleName            = local.member_account_eventbridge_rule_name
    EventBusName                   = local.event_bus_name
    ForceDeployment                = "1"
    KmsKeyId                       = aws_kms_key.key.key_id
    OrganizationId                 = var.current.organization_id
    PrimaryRegion                  = var.deployment_regions[0]
    RestoreVaultName               = local.member_account_restore_vault_name
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
  call_as        = local.cfn_call_as
  regions        = var.deployment_regions
  deployment_targets {
    organizational_unit_ids = var.deployment_targets
  }

  operation_preferences {
    failure_tolerance_percentage = 10
    max_concurrent_percentage    = 100
    region_concurrency_type      = "PARALLEL"
  }
}
