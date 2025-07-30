module "tf_state_bucket" {
  source = "../s3"
  count  = var.terraform_state_bucket_name == "" ? 1 : 0

  bucket_prefix = local.bucket_prefix
}