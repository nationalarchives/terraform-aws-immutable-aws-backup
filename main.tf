locals {
  # Internal
  account_id                                        = data.aws_caller_identity.current.account_id
  organization_id                                   = data.aws_organizations_organization.org.id
  partition_id                                      = data.aws_partition.current.partition
  region                                            = data.aws_region.current.region
  member_account_deployment_helper_role_name_suffix = "-deployment-helper"
}

module "deployment_helper_lambda" {
  source = "./modules/deployment-helper-lambda"

  lambda_function_name                              = join("", [var.central_account_resource_name_prefix, "deployment-helper"])
  member_account_deployment_helper_role_arn_pattern = join("", ["arn:", local.partition_id, ":iam::*:role/", var.member_account_resource_name_prefix, "*", local.member_account_deployment_helper_role_name_suffix])
  organization_id                                   = local.organization_id
  terraform_state_bucket_name                       = var.terraform_state_bucket_name
}

module "service_deployment" {
  source   = "./modules/service-deployment"
  for_each = var.deployments

  service_name       = each.key
  backup_tag_key     = each.value.backup_tag_key
  deployment_targets = each.value.targets
  max_retention_days = each.value.max_retention_days
  min_retention_days = each.value.min_retention_days
  plans              = each.value.plans
  restores_enabled   = each.value.restores_enabled
  retained_vaults    = each.value.retained_vaults

  central_account_resource_name_prefix              = var.central_account_resource_name_prefix
  central_backup_service_linked_role_arn            = local.backup_service_linked_role_arn
  central_backup_service_role_arn                   = module.backup_service_role.role.arn
  central_deployment_helper_role_arn                = module.deployment_helper_lambda.lambda_role_arn
  central_deployment_helper_topic_arn               = module.deployment_helper_lambda.sns_topic.arn
  deployment_regions                                = [local.region]
  member_account_deployment_helper_role_name_suffix = local.member_account_deployment_helper_role_name_suffix
  member_account_resource_name_prefix               = var.member_account_resource_name_prefix
}
