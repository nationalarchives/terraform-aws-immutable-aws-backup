# Immutable AWS Backup Terraform module

An open-source Terraform module to deploy and orchestrate AWS Backup to creating fully immutable backups within an AWS Organization.

## Usage

```hcl
module "immutable_aws_backup" {
  source = "nationalarchives/immutable-aws-backup/aws"
  # It's recommended to explicitly constrain the version number to avoid unexpected or unwanted changes.

  central_account_resource_name_prefix = "immutable-aws-backup-"
  member_account_resource_name_prefix  = "orgdeploy-immutable-aws-backup-"
  terraform_state_bucket_name          = "my-terraform-state-bucket"

  deployments = {
    "website-service" = {
      targets            = ["ou-abcd-defghijk"]
      min_retention_days = 7
      max_retention_days = 90
      restores_enabled   = false
      backup_tag_key     = "BackupPlan"
      plans = {
        "GFS-7-28-90" : {
          require_plan_name_resource_tag = true
          use_logically_air_gapped_vault = false
          rules = [
            {
              name                = "daily",
              schedule_expression = "cron(0 3 ? * * *)"
              delete_after_days   = 7
            },
            {
              name                = "weekly",
              schedule_expression = "cron(0 3 ? * 2 *)"
              delete_after_days   = 28
            },
            {
              name                = "monthly",
              schedule_expression = "cron(0 3 1 * ? *)"
              delete_after_days   = 90
            }
          ]
        }
      }
    }
  }
}
```
