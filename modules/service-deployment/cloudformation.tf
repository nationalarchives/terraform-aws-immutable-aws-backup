locals {
  region_deployment_order = var.deployment_regions
}

resource "aws_cloudformation_stack_set" "member_account_deployments" {
  name             = local.member_account_resource_name_prefix
  description      = "Centralised AWS Backup for ${var.service_name}."
  capabilities     = ["CAPABILITY_NAMED_IAM"]
  permission_model = "SERVICE_MANAGED"
  call_as          = "DELEGATED_ADMIN"

  # Try to do as much as possible in native CloudFormation, but some things, like dynamic lists, are only possible in Terraform.
  # jsonencode(jsondecode(...)) used to minify the file.
  template_body = jsonencode(jsondecode(templatefile("${path.module}/templates/stackset.json.tftpl", {
    central_backup_vault_arn_templates = [for i in local.central_backup_vault_arns_template : { "Fn::Sub" : replace(replace(i, "<REGION>", "$${AWS::Region}"), var.current.account_id, "$${CentralAccountId}") }],
  })))

  parameters = {
    BackupServiceLinkedRoleArn  = var.central_backup_service_linked_role_arn
    BackupServiceRoleName       = local.member_account_backup_service_role_name
    BackupServiceRolePrincipals = join(", ", [module.backup_ingest_sfn_role.role.arn])
    BackupVaultName             = local.member_account_backup_vault_name
    CentralAccountId            = var.current.account_id
    DeploymentHelperRoleArn     = var.central_deployment_helper_role_arn
    DeploymentHelperRoleName    = local.member_account_deployment_helper_role_name
    DeploymentHelperTopicName   = var.central_deployment_helper_topic_name
    DeploymentRegions           = join(", ", var.deployment_regions)
    EventBridgeRuleName         = local.member_account_eventbridge_rule_name
    EventBusName                = local.event_bus_name
    ForceDeployment             = "1"
    KmsKeyId                    = aws_kms_key.key.key_id
    OrganizationId              = var.current.organization_id
    PrimaryRegion               = var.deployment_regions[0]
    RestoreVaultName            = local.member_account_restore_vault_name
  }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  operation_preferences {
    failure_tolerance_percentage = 10
    max_concurrent_percentage    = 100
    region_concurrency_type      = "SEQUENTIAL"
    region_order                 = local.region_deployment_order
  }

  lifecycle {
    ignore_changes = [administration_role_arn]
  }
}

resource "aws_cloudformation_stack_instances" "member_account_deployments" {
  stack_set_name = aws_cloudformation_stack_set.member_account_deployments.name
  call_as        = "DELEGATED_ADMIN"
  regions        = var.deployment_regions
  deployment_targets {
    organizational_unit_ids = var.deployment_targets
  }

  operation_preferences {
    failure_tolerance_percentage = 10
    max_concurrent_percentage    = 100
    region_concurrency_type      = "SEQUENTIAL"
    region_order                 = local.region_deployment_order
  }
}
