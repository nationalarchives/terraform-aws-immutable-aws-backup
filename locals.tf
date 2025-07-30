locals {
  terraform_state_bucket_name = (
    var.terraform_state_bucket_name != "" ? var.terraform_state_bucket_name :
    module.tf_state_bucket[0].s3_bucket_name
  )
}