variable "additional_kms_statements" {
  description = "Additional policy statements to be added to the KMS Key Policy."
  type        = list(map(any))
  default     = []
}

variable "backup_tag_key" {
  description = "The key of the tag to be used during backup resource selection."
  type        = string
  default     = ""
}

variable "central_backup_service_role_arn" {
  description = "The ARN of the central backup service role, used to copy backups between vaults."
  type        = string
}

variable "central_backup_service_linked_role_arn" {
  description = "The ARN of the AWS Backup service-linked role in the central account. Required to be added to custom KMS Key Policies in member accounts."
  type        = string
  default     = ""
}

variable "central_deployment_helper_role_arn" {
  description = "The ARN of the central deployment helper Lambda role, used in the trust policy of the member account Deployment Helper role."
  type        = string
  default     = ""
}

variable "central_deployment_helper_topic_arn" {
  description = "The ARN of the central deployment helper SNS Topic."
  type        = string
  default     = ""
}

variable "central_account_resource_name_prefix" {
  description = "Prefix to be used for resource names in the central account."
  type        = string
  default     = ""
}
variable "deployment_targets" {
  description = "A list of organizational unit IDs deploy the stack set to."
  type        = list(string)
  default     = []
}

variable "create_member_account_resources" {
  description = "Set to true to create resources in member accounts, such as the cross-account orchestration role."
  type        = bool
  default     = false
}

variable "region" {
  description = "The AWS region where resources are deployed."
  type        = string
}

variable "deployment_name" {
  description = "The name of the deployment."
  type        = string
}

variable "max_retention_days" {
  description = "The maximum number of days to retain backups."
  type        = number
  default     = null

  validation {
    condition     = var.max_retention_days != null ? alltrue(flatten([for k, p in var.plans : [for r in p["rules"] : r["delete_after_days"] <= var.max_retention_days]])) : true
    error_message = "delete_after_days must be set to a value less than the max_retention_days."
  }
  validation {
    condition     = anytrue([for k, p in var.plans : p.use_logically_air_gapped_vault]) ? try(var.max_retention_days > 0, false) : true
    error_message = "max_retention_days must be set when a plan uses a Logically Air Gapped Vault."
  }
}

variable "member_account_deployment_helper_role_name_suffix" {
  type = string
}

variable "member_account_resource_name_prefix" {
  description = "Prefix to be used for resource names in member accounts."
  type        = string
  default     = ""
}

variable "min_retention_days" {
  description = "The minimum number of days to retain backups."
  type        = number
  default     = null

  validation {
    condition     = (var.min_retention_days != null && var.max_retention_days != null) ? var.min_retention_days <= var.max_retention_days : true
    error_message = "If both are provided, min_retention_days must be less than or equal to max_retention_days."
  }
  validation {
    condition     = anytrue([for k, p in var.plans : p.use_logically_air_gapped_vault]) ? try(var.min_retention_days >= 7, false) : true
    error_message = "min_retention_days must be at least 7 when a plan uses a Logically Air Gapped Vault."
  }
  validation {
    condition     = var.min_retention_days != null ? alltrue(flatten([for k, p in var.plans : [for r in p["rules"] : (r["delete_after_days"] == null || r["delete_after_days"] >= var.min_retention_days)]])) : true
    error_message = "If provided, no backup rules can have a delete_after_days value less than the minimum retention days."
  }
}

variable "plans" {
  description = "A list of rules to be created for the backup plan."
  type = map(object({
    continuous_backup_schedule_expression = optional(string, "cron(0 0 ? * * *)"), # Schedule for creating continuous backups, if enabled.
    create_continuous_backups             = optional(bool, false),                 # Create continuous backups for resources that support it to enable local PITR, there is no copy action for these backups.
    intermediate_retention_days           = optional(number),                      # Number of days to retain backups in the intermediate vault.
    local_retention_days                  = optional(number),                      # Number of days to retain backups in the member account vault. If not specified, defaults to delete_after_days.
    require_plan_name_resource_tag        = optional(bool, true),
    snapshot_from_continuous_backups      = optional(bool, true), # Generate continuous backups for resources that support it and then snapshot from them. These backups do not copy but act as a source for the backup jobs created by the rules. Currently only S3 is supported.
    use_logically_air_gapped_vault        = optional(bool, false),
    rules = list(object({
      delete_after_days           = optional(number) # Number of days to retain backups in the central vault, over
      intermediate_retention_days = optional(number) # Number of days to retain backups in the intermediate vault, overrides the plan's intermediate_retention_days.
      local_retention_days        = optional(number) # Number of days to retain backups in the member account vault. If not specified, defaults to delete_after_days.
      name                        = optional(string),
      schedule_expression         = string,
    }))
  }))
  default = {}
}

variable "restores_enabled" {
  description = "Allow restores from the backup vaults."
  type        = bool
  default     = false
}

variable "retained_vaults" {
  description = "A list of vaults to be retained in member accounts."
  type = list(object({
    min_retention_days             = number
    max_retention_days             = number
    use_logically_air_gapped_vault = optional(bool, false)
  }))
  default = []
}

variable "service_name" {
  description = "The name of the service to be backed up."
  type        = string
}
