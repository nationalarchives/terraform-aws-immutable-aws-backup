variable "current" {
  description = "The current AWS account ID, partition, and region."
  type = object({
    organization_id : string
    partition : string
    region : string
  })
}

variable "deployment_regions" {
  description = "The AWS regions where the deployment helper will be deployed."
  type        = list(string)
}

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
