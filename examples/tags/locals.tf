locals {
  account_id = data.aws_caller_identity.current.account_id

  resource_name_prefix = "aws-backup-"

  schedule_daily   = "cron(0 3 ? * * *)"
  schedule_weekly  = "cron(0 3 ? * 2 *)"
  schedule_monthly = "cron(0 3 1 * ? *)"

  ca_default_plans = {
    "ca-prod-important" : {
      require_plan_name_resource_tag = true
      use_logically_air_gapped_vault = true
      start_backup_window_minutes    = 60
      local_retention_days           = 2
      intermediate_retention_days    = 2
      rules = [
        {
          name                = "daily",
          schedule_expression = local.schedule_daily
          delete_after_days   = 7
        },
        {
          name                = "weekly",
          schedule_expression = local.schedule_weekly
          delete_after_days   = 8
        },
        {
          name                = "monthly",
          schedule_expression = local.schedule_monthly
          delete_after_days   = 9
        }
      ]
    }
  }
}
