# Immutable AWS Backup Terraform module

An open-source Terraform module to deploy and orchestrate AWS Backup for creating fully immutable backups within an AWS Organization.

- Manages the deployment of Backup Vaults to member accounts using CloudFormation StackSets.
- Stores backups in a central AWS account to protect against account closure or suspension.
- Protection against KMS Key deletion through using AWS Managed and AWS Owned keys.
- Support for Logically Air Gapped Vaults, with logic to use them only for supported resource types.
- (Optional) Resource selection using tags.
- Implements AWS best practices and guidance for security and cost.
- Simplifies the process of configuring AWS Backup plans.

See [Why use this module?](https://nationalarchives.github.io/terraform-aws-immutable-aws-backup/why-use-this-module/) in our docs to understand the issues this module solves and how it works.

## Architecture and deployment

The module is designed to be deployed in a dedicated account within an AWS Organization, this account must be [delegated certain abilities for the module to function](https://nationalarchives.github.io/terraform-aws-immutable-aws-backup/usage/). Go to our [Architecture](https://nationalarchives.github.io/terraform-aws-immutable-aws-backup/architecture/) documentation for a more detailed explanation of the architecture and how the module works.

![Architecture Diagram](https://raw.githubusercontent.com/nationalarchives/terraform-aws-immutable-aws-backup/refs/heads/main/docs/assets/images/backup-architecture.png)

## Example Usage

```hcl
module "immutable_aws_backup" {
  source = "nationalarchives/immutable-aws-backup/aws"
  # It's recommended to explicitly constrain the version number to avoid unexpected or unwanted changes.

  central_account_resource_name_prefix = "immutable-aws-backup-"
  member_account_resource_name_prefix  = "orgdeploy-immutable-aws-backup-"
  terraform_state_bucket_name          = "my-terraform-state-bucket"

  deployments = {
    "website-service" = {
      backup_targets     = ["ou-abcd-defghijk"]
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

## About The National Archives, UK

We are a non-ministerial department, and the official archive and publisher for the UK Government, and for England and Wales. We are the guardians of over 1,000 years of iconic national documents.

We are expert advisers in information and records management and are a cultural, academic and heritage institution. We fulfil a leadership role for the archive sector and work to secure the future of physical and digital records.

Find out more about [what we do](https://www.nationalarchives.gov.uk/about/our-role/what-we-do/).
