locals {
  terraform_state_bucket_name = (
    var.terraform_state_bucket_name != "" ? var.terraform_state_bucket_name :
    module.tf_state_bucket[0].s3_bucket_name
  )

  terraform_state_bucket_arn = (
    var.terraform_state_bucket_name != "" ? "arn:${var.current.partition}:s3:::${var.terraform_state_bucket_name}" :
    module.tf_state_bucket[0].s3_bucket_arn
  )
}