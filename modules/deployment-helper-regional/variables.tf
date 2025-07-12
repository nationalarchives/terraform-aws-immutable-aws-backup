variable "current" {
  description = "Current AWS partition and region."
  type = object({
    organization_id = string
    partition       = string
  })
}

variable "lambda_function_name" {
  description = "The name of the Lambda function."
  type        = string
}

variable "lambda_role_arn" {
  description = "The ARN of the Lambda execution role."
  type        = string
}

variable "region" {
  description = "The AWS region where the module will be deployed."
  type        = string
}

variable "terraform_state_bucket_name" {
  description = "The name of the S3 bucket to store Terraform state files."
  type        = string
}
