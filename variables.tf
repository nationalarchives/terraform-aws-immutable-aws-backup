variable "central_account_resource_name_prefix" {
  type        = string
  description = "Prefix to be used for resource names in the central account."
}

variable "deployments" {
  type = map(object({
    admin_role_names                = optional(list(string), []) # Names of IAM roles that have admin access to the deployment. E.g. can manage the backup vaults in member accounts.
    allow_backup_targets_to_restore = optional(bool, false)
    backup_tag_key                  = optional(string)
    backup_targets                  = list(string)
    max_retention_days              = optional(number)
    min_retention_days              = optional(number)
    plans = map(object({
      complete_backup_window_minutes        = optional(number)
      continuous_backup_schedule_expression = optional(string, "cron(0 0 ? * * *)") # Schedule for creating continuous backups, if enabled.
      create_continuous_backups             = optional(bool, false)                 # Create continuous backups for resources that support it to enable local PITR, there is no copy action for these backups.
      intermediate_retention_days           = optional(number)                      # Number of days to retain backups in the intermediate vault.
      local_retention_days                  = optional(number)                      # Number of days to retain backups in the member account vault. If not specified, defaults to delete_after_days.
      require_plan_name_resource_tag        = optional(bool, true)
      snapshot_from_continuous_backups      = optional(bool, true) # Generate continuous backups for resources that support it and then snapshot from them. These backups do not copy but act as a source for the backup jobs created by the rules. Currently only S3 is supported.
      start_backup_window_minutes           = optional(number)
      use_logically_air_gapped_vault        = optional(bool, false)
      rules = list(object({
        complete_backup_window_minutes = optional(number)
        delete_after_days              = optional(number) # Number of days to retain backups in the central vault, over
        intermediate_retention_days    = optional(number) # Number of days to retain backups in the intermediate vault, overrides the plan's intermediate_retention_days.
        local_retention_days           = optional(number) # Number of days to retain backups in the member account vault. If not specified, defaults to delete_after_days.
        name                           = optional(string)
        schedule_expression            = string
        start_backup_window_minutes    = optional(number)
      }))
    }))
    retained_vaults = optional(list(object({
      min_retention_days             = number
      max_retention_days             = number
      use_logically_air_gapped_vault = optional(bool, false)
    })), [])
  }))
}

variable "member_account_resource_name_prefix" {
  type        = string
  description = "Prefix to be used for resource names in member accounts."
}

variable "terraform_state_bucket_name" {
  type        = string
  description = "Name of S3 bucket for custom Terraform deployments, if left at default, S3 bucket will be created"
  default     = ""
}
