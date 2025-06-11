variable "central_account_resource_name_prefix" {
  type        = string
  description = "Prefix to be used for resource names in the central account."
}

variable "deployments" {
  type = map(object({
    backup_tag_key     = optional(string),
    max_retention_days = number,
    min_retention_days = number,
    plans = map(object({
      require_plan_name_resource_tag        = optional(bool, true),
      use_continuous_backups                = optional(bool, true),                  # Use continuous backups for resources that support it. These backups do not copy but act as a source for the backup jobs created by the rules.
      continuous_backup_schedule_expression = optional(string, "cron(0 0 ? * * *)"), # Schedule for creating continuous backups, if enabled.
      use_logically_air_gapped_vault        = optional(bool, false),
      rules = list(object({
        schedule_expression = string,
        name                = string,
        delete_after_days   = number
      }))
    })),
    restores_enabled = bool,
    retained_vaults = optional(list(object({
      min_retention_days             = number,
      max_retention_days             = number,
      use_logically_air_gapped_vault = optional(bool, false)
    })), [])
    targets = list(string),
  }))
  description = "Map of service deployments with their configurations."
}

variable "member_account_resource_name_prefix" {
  type        = string
  description = "Prefix to be used for resource names in member accounts."
}

variable "terraform_state_bucket_name" {
  type        = string
  description = "Name of the S3 bucket used for storing Terraform state files for custom Terraform deployments."
}
