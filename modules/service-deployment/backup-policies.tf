
locals {
  # Resource types (documented at https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_backup_syntax.html#backup-plan-selections)
  resource_types_with_lag_support = [
    "arn:aws:ec2:*:*:instance/*",                  # EC2
    "arn:aws:s3:::*",                              # S3
    "arn:aws:ec2:*:*:volume/*",                    # EBS
    "arn:aws:rds:*:*:cluster:*",                   # Aurora / Aurora DSQL / DocumentDB / Neptune (RDS Multi-AZ clusters do not currently support cross-Region or cross-account copy)
    "arn:aws:elasticfilesystem:*:*:file-system/*", # EFS
    "arn:aws:storagegateway:*:*:gateway/*",        # Storage Gateway
    "arn:aws:timestream:*:*:database/*",           # Timestream
    "arn:aws:backup-gateway:*:*:vm/*",             # Backup Gateway Virtual Machines
    "arn:aws:cloudformation:*:*:stack/*",          # CloudFormation
    "arn:aws:dynamodb:*:*:table/*",                # DynamoDB
  ]
  resource_types_without_lag_support = [
    "arn:aws:fsx:*:*:file-system/*",  # FSx File Systems (FSx for ONTAP does not support LAG vaults)
    "arn:aws:fsx:*:*:volume/*",       # FSx File Systems (FSx for ONTAP does not support LAG vaults)
    "arn:aws:rds:*:*:db:*",           # RDS Database Instance
    "arn:aws:redshift:*:*:cluster:*", # Redshift
    "arn:aws:ssm-sap:*:*:HANA/*",     # SAP HANA
  ]
  resource_types_that_snapshot_from_continuous_backups = [
    # These resources support continuous backups and use these as a source for periodic backups.
    "arn:aws:s3:::*", # S3
  ]
  resource_types_with_continuous_backup_support = concat(
    local.resource_types_that_snapshot_from_continuous_backups,
    [
      # These resources support continuous backups, but only for PITR recovery within the source account.
      "arn:aws:rds:*:*:db:*",       # RDS Database Instance
      "arn:aws:ssm-sap:*:*:HANA/*", # SAP HANA
      # Aurora is not included as it can't be targetted by ARN
    ]
  )

  # Backup Policies don't support "$region" so we need a plan per region to use the correct vault ARNs.
  plan_regions = { for region in var.deployment_regions : region => {
    name : region #
    shortname : lookup(local.aws_region_abbreviations, region, region),
    intermediate_vault_arn : replace(local.intermediate_vault_arn_template, "<REGION>", region)
    current_lag_vault_arn : replace(local.current_lag_vault_arn_template, "<REGION>", region)
    current_standard_vault_arn : replace(local.current_standard_vault_arn_template, "<REGION>", region)
  } }

  plans = merge(
    # Pass through the plans as defined by the caller
    { for k, v in var.plans : "${k}-std" => merge(v, { lag_plan : false, continuous_plan : false, tag_value : k }) },
    # If using a Logically Air Gapped Vault, we need separate plans for the resource selections
    local.create_lag_resources ? { for k, v in var.plans : "${k}-lag" => merge(v, { lag_plan : true, continuous_plan : false, tag_value : k }) if v["use_logically_air_gapped_vault"] } : {},
    # If creating continuous backups, we need separate plans for the continuous backups - different lifecycle and they need to exist before the rules that snapshot from them.
    { for k, v in var.plans : "${k}-pitr" => merge(v, { lag_plan : false, continuous_plan : true, tag_value : k, start_backup_window_minutes : null, complete_backup_window_minutes : null, rules : [{ name : "${k}-continuous-backups", schedule_expression : v["continuous_backup_schedule_expression"], delete_after_days : 35, start_backup_window_minutes : null, complete_backup_window_minutes : null, recovery_point_tags : merge(var.recovery_point_tags, v["recovery_point_tags"]) }] }) if v["create_continuous_backups"] || v["snapshot_from_continuous_backups"] },
  )

  policy_content = jsonencode({
    plans : merge([
      for region in local.plan_regions : {
        for plan_name, plan in local.plans : join("-", [local.central_account_resource_name_prefix, plan_name, region["shortname"]]) => {
          "regions" : { "@@assign" : [region["name"]] },
          "rules" : { for rule_idx, rule in plan["rules"] : coalesce(rule["name"], rule_idx) =>
            # Nested k, v for expression filters out null values (logic below)
            { for k, v in {
              "complete_backup_window_minutes" : { "@@assign" : try(coalesce(rule["complete_backup_window_minutes"], plan["complete_backup_window_minutes"]), null) },
              "copy_actions" : plan["continuous_plan"] ? null : {
                "${plan["lag_plan"] ? region["current_lag_vault_arn"] : region["intermediate_vault_arn"]}" : { "target_backup_vault_arn" : { "@@assign" : plan["lag_plan"] ? region["current_lag_vault_arn"] : region["intermediate_vault_arn"] } }
              },
              "enable_continuous_backup" : { "@@assign" : plan["continuous_plan"] },
              "lifecycle" : {
                "delete_after_days" : { "@@assign" : rule["delete_after_days"] },
              },
              "schedule_expression" : { "@@assign" : rule["schedule_expression"] },
              "start_backup_window_minutes" : { "@@assign" : try(coalesce(rule["start_backup_window_minutes"], plan["start_backup_window_minutes"]), null) },
              "recovery_point_tags" : merge(
                { for k, v in var.recovery_point_tags : k => { "tag_key" : { "@@assign" : k }, "tag_value" : { "@@assign" : v } } },
                { for k, v in plan["recovery_point_tags"] : k => { "tag_key" : { "@@assign" : k }, "tag_value" : { "@@assign" : v } } },
                { for k, v in rule["recovery_point_tags"] : k => { "tag_key" : { "@@assign" : k }, "tag_value" : { "@@assign" : v } } },
                plan["continuous_plan"] ? null : merge(
                  { "${local.local_retention_days_tag}" : { "tag_key" : { "@@assign" : local.local_retention_days_tag }, "tag_value" : { "@@assign" : coalesce(rule["local_retention_days"], plan["local_retention_days"], rule["delete_after_days"], -1) } } },
                  plan["lag_plan"] ? {} : { "${local.intermediate_retention_days_tag}" : { "tag_key" : { "@@assign" : local.intermediate_retention_days_tag }, "tag_value" : { "@@assign" : coalesce(rule["intermediate_retention_days"], plan["intermediate_retention_days"], 7) } } }
                )
              )
              "target_backup_vault_name" : { "@@assign" : local.member_account_backup_vault_name }
            } : k => v if(v != null && try(v["@@assign"], true) != null) }
          }
          "selections" : {
            "resources" : {
              "${plan["require_plan_name_resource_tag"] ? "supported-resources-with-tag" : "all-supported-resources"}" : {
                "iam_role_arn" : { "@@assign" : "arn:aws:iam::$account:role/${local.member_account_backup_service_role_name}" },
                "resource_types" : { "@@assign" : toset(concat(
                  plan["continuous_plan"] && plan["create_continuous_backups"] ? local.resource_types_with_continuous_backup_support : [],
                  plan["continuous_plan"] && plan["snapshot_from_continuous_backups"] ? local.resource_types_that_snapshot_from_continuous_backups : [],
                  plan["use_logically_air_gapped_vault"] && !plan["continuous_plan"] ? (plan["lag_plan"] ? local.resource_types_with_lag_support : local.resource_types_without_lag_support) : [],
                  !plan["continuous_plan"] && !plan["use_logically_air_gapped_vault"] ? ["*"] : [], # If not using LAG or continuous backups, select all resources
                )) },
                "conditions" : !plan["require_plan_name_resource_tag"] ? {} : {
                  "string_equals" : {
                    "require_resource_tag" : {
                      "condition_key" : { "@@assign" : "aws:ResourceTag/${var.backup_tag_key}" },
                      "condition_value" : { "@@assign" : plan["tag_value"] }
                    }
                  }
                }
              }
            }
          }
        }
      }
    ]...)
  })

}

resource "aws_organizations_policy" "backup_policy" {
  name        = local.central_account_resource_name_prefix
  description = ""
  type        = "BACKUP_POLICY"
  content     = local.policy_content
}

resource "aws_organizations_policy_attachment" "backup_policy" {
  for_each = toset(var.deployment_targets)

  policy_id = aws_organizations_policy.backup_policy.id
  target_id = each.key
}
