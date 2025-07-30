module "tf_state_bucket" {
  source = "../s3"
  count  = var.terraform_state_bucket_name == "" ? 1 : 0

  central_account_resource_name_prefix = var.central_account_resource_name_prefix
}