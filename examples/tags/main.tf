module "aws_backup" {
  source = "../../"
  # source  = "nationalarchives/organizations-immutable-aws-backup/aws"
  # version = "0.1.0"

  central_account_resource_name_prefix = local.resource_name_prefix
  member_account_resource_name_prefix  = "org-${local.resource_name_prefix}"
  terraform_state_bucket_name          = var.terraform_state_bucket
  deployments = {
    "ca-prod" = {
      backup_targets     = [module.ou_data_lookup.by_name_path["Workloads / Serverless / CA / RSA CA"].id]
      min_retention_days = 7
      max_retention_days = 12
      restores_enabled   = true
      backup_tag_key     = "BackupPolicy"
      plans              = local.ca_default_plans
    }
  }
}
