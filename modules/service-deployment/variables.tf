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

variable "max_retention_days" {
  description = "The maximum number of days to retain backups."
  type        = number
  default     = 365

  validation {
    condition     = alltrue(flatten([for k, p in var.plans : [for r in p["rules"] : r["delete_after_days"] <= var.max_retention_days]]))
    error_message = "No backup rules can have a delete_after_days value less than the maximum retention days."
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
  default     = 7

  validation {
    condition     = alltrue(flatten([for k, p in var.plans : [for r in p["rules"] : r["delete_after_days"] >= var.min_retention_days]]))
    error_message = "No backup rules can have a delete_after_days value less than the minimum retention days."
  }
}

variable "plans" {
  description = "A list of rules to be created for the backup plan."
  type = map(object({
    require_plan_name_resource_tag = optional(bool, true)
    use_logically_air_gapped_vault = optional(bool, false)
    rules = list(object({
      delete_after_days   = optional(number)
      name                = optional(string)
      schedule_expression = string
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
