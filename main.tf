locals {
  # Internal
  account_id         = data.aws_caller_identity.current.account_id
  organization_id    = data.aws_organizations_organization.org.id
  partition_id       = data.aws_partition.current.partition
  region             = data.aws_region.current.region
  deployment_regions = [local.region]

  # Member account deployment role names are templated here but used throughout this module and submodules.
  member_account_deployment_helper_role_name_template = "${var.member_account_resource_name_prefix}<SERVICE>-deployment-helper-<REGION>"
  member_account_deployment_helper_role_names         = flatten([for service_name, deployment in var.deployments : [for r in local.deployment_regions : replace(replace(local.member_account_deployment_helper_role_name_template, "<SERVICE>", service_name), "<REGION>", r)]])
}

module "deployment_helper" {
  source = "./modules/deployment-helper"
  current = {
    organization_id = local.organization_id
    partition       = local.partition_id
    region          = local.region
  }
  deployment_regions                                 = local.deployment_regions
  lambda_function_name                               = join("", [var.central_account_resource_name_prefix, "deployment-helper"])
  member_account_deployment_helper_role_arn_patterns = [for i in local.member_account_deployment_helper_role_names : join("", ["arn:", local.partition_id, ":iam::*:role/", i])]
  terraform_state_bucket_name                        = local.terraform_state_bucket_name
}

module "deployment" {
  source   = "./modules/service-deployment"
  for_each = var.deployments

  service_name       = each.key
  admin_role_names   = each.value.admin_role_names
  backup_tag_key     = each.value.backup_tag_key
  deployment_targets = each.value.backup_targets
  max_retention_days = each.value.max_retention_days
  min_retention_days = each.value.min_retention_days
  plans              = each.value.plans
  restores_enabled   = each.value.allow_backup_targets_to_restore
  retained_vaults    = each.value.retained_vaults

  current = {
    account_id      = local.account_id
    organization_id = local.organization_id
    partition       = local.partition_id
    region          = local.region
  }
  central_account_resource_name_prefix                = var.central_account_resource_name_prefix
  central_backup_service_linked_role_arn              = local.backup_service_linked_role_arn
  central_deployment_helper_role_arn                  = module.deployment_helper.lambda_role.arn
  central_deployment_helper_topic_name                = module.deployment_helper.sns_topic.name
  deployment_regions                                  = local.deployment_regions
  member_account_deployment_helper_role_name_template = replace(local.member_account_deployment_helper_role_name_template, "<SERVICE>", each.key)
  member_account_resource_name_prefix                 = var.member_account_resource_name_prefix
}

module "tf_state_bucket" {
  source = "./modules/s3"

  central_account_resource_name_prefix = var.central_account_resource_name_prefix
}