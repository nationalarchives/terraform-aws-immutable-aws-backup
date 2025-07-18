variable "backup_policies" {
  type = object({
    intermediate_retention_days_tag = string
    local_retention_days_tag        = string
  })
}

variable "backup_vaults" {
  type = object({
    current_vault_configuration = string
    intermediate_vault_name     = string
    lag_vault_prefix            = string
    lag_vaults                  = list(string)
    standard_vault_prefix       = string
    standard_vaults             = list(string)
  })
}

variable "current_aws_account_id" {
  description = "The AWS account ID where Terraform is being executed."
  type        = string
}

variable "current_aws_partition" {
  description = "The current AWS partition (e.g., aws, aws-cn, aws-us-gov) where Terraform is being executed."
  type        = string
}

variable "current_aws_region" {
  description = "The current AWS region where Terraform is being executed."
  type        = string
}

variable "deployment" {
  type = object({
    backup_service_role_arn     = string
    ou_paths_including_children = list(string),
  })
}

variable "eventbridge" {
  type = object({
    bus_name               = string
    forwarder_iam_role_arn = string
  })
}

variable "kms" {
  type = object({
    kms_key_alias   = string
    kms_key_id      = string
    kms_key_policy  = string
    primary_key_arn = string
  })
}

variable "member_account_backup_service_role_name" {
  description = "The name of the backup service role in member accounts."
  type        = string
}

variable "member_account_eventbridge_rule_name" {
  description = "The name of the EventBridge rule in member accounts."
  type        = string
}

variable "member_account_backup_vault_name" {
  description = "The name of the backup vault in member accounts."
  type        = string
}

variable "ram" {
  type = object({
    create_lag_shares  = bool
    lag_share_name     = string
    target_account_ids = list(string),
  })
}

variable "region" {
  description = "The AWS region where the resources will be deployed."
  type        = string
}

variable "stepfunctions" {
  type = object({
    ingest_eventbridge_target_role_arn = string
    ingest_state_machine_name          = string
    ingest_state_machine_role_arn      = string
    ingest_state_role_arn              = string
  })
}

