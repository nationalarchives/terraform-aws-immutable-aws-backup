variable "lambda_function_name" {
  description = "The name of the Lambda function."
  type        = string
}

variable "member_account_deployment_helper_role_arn_pattern" {
  description = "The pattern to use to restrict role assumption to the member account Deployment Helper roles."
  type        = string
}
variable "terraform_state_bucket_name" {
  description = "The name of the S3 bucket to store Terraform state files."
  type        = string
}

variable "organization_id" {
  description = "The ID of the AWS organization."
  type        = string
}
