module "aws_backup" {
  source = "../../"
  # source  = "nationalarchives/organizations-immutable-aws-backup/aws"
  # version = "0.1.0"

  central_account_resource_name_prefix = local.resource_name_prefix
  member_account_resource_name_prefix  = "org-${local.resource_name_prefix}"
  deployments = {
    "ca-prod" = {
      backup_targets                  = [module.ou_data_lookup.by_name_path["Workloads / Serverless / CA / RSA CA"].id]
      min_retention_days              = 7
      max_retention_days              = 90
      allow_backup_targets_to_restore = true
      backup_tag_key                  = "BackupPolicy"
      plans                           = local.ca_default_plans
    }
  }
}
