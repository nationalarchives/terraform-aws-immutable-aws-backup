locals {
  terraform_state_bucket_name = (
    var.terraform_state_bucket_name == "" ? module.tf_state_bucket.s3_bucket_name :
    var.terraform_state_bucket_name
  )
}