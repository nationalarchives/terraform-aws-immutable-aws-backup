module "deployment_helper_regional" {
  source   = "../deployment-helper-regional"
  for_each = toset(var.deployment_regions)

  region = each.value
  current = {
    organization_id = var.current.organization_id
    partition       = var.current.partition
  }
  lambda_function_name        = var.lambda_function_name
  lambda_role_arn             = module.lambda_role.role.arn
  terraform_state_bucket_name = local.terraform_state_bucket_name
}
