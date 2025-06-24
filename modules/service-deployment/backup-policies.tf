
locals {
  # Resource types (documented at https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_backup_syntax.html#backup-plan-selections)
  resource_types_with_lag_support = [
    # TODO: Add FSx support, difficult because support depends on the FSx type and ARNs are all the same
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

  plans = merge(
    # Pass through the plans as defined by the caller
    { for k, v in var.plans : "${k}-to-standard" => merge(v, { lag_plan : false, continuous_plan : false, tag_value : k }) },
    # If using a Logically Air Gapped Vault, we need separate plans for the resource selections
    local.create_lag_resources ? { for k, v in var.plans : "${k}-to-lag" => merge(v, { lag_plan : true, continuous_plan : false, tag_value : k }) if v["use_logically_air_gapped_vault"] } : {},
    # If creating continuous backups, we need separate plans for the continuous backups - different lifecycle and they need to exist before the rules that snapshot from them.
    { for k, v in var.plans : "${k}-continuous-backups" => merge(v, { lag_plan : false, continuous_plan : true, tag_value : k, rules : [{ name : "${k}-continuous-backups", schedule_expression : v["continuous_backup_schedule_expression"], delete_after_days : 35 }] }) if v["create_continuous_backups"] || v["snapshot_from_continuous_backups"] },
  )

  policy_content = jsonencode({
    "plans" : { for plan_name, plan in local.plans : plan_name => {
      "regions" : { "@@assign" : [data.aws_region.current.id] },
      "rules" : { for rule_idx, rule in plan["rules"] : coalesce(rule["name"], rule_idx) => {
        "schedule_expression" : { "@@assign" : rule["schedule_expression"] },
        "target_backup_vault_name" : { "@@assign" : local.member_account_backup_vault_name },
        "enable_continuous_backup" : { "@@assign" : plan["continuous_plan"] },
        "start_backup_window_minutes" : { "@@assign" : 60 },
        "lifecycle" : {
          "delete_after_days" : { "@@assign" : rule["delete_after_days"] },
        },
        "copy_actions" : plan["continuous_plan"] ? {} : {
          "${plan["lag_plan"] ? local.current_lag_vault.arn : aws_backup_vault.intermediate.arn}" : {
            "target_backup_vault_arn" : { "@@assign" : plan["lag_plan"] ? local.current_lag_vault.arn : aws_backup_vault.intermediate.arn }
          }
        },
        "recovery_point_tags" : plan["continuous_plan"] ? {} : merge(
          {
          "${local.local_retention_days_tag}" : { "tag_key" : { "@@assign" : local.local_retention_days_tag }, "tag_value" : { "@@assign" : coalesce(rule["local_retention_days"], plan["local_retention_days"], rule["delete_after_days"], -1) } 
          }
        },
        (!plan["lag_plan"]) ? {
          "${local.intermediate_retention_days_tag}" : { "tag_key" : { "@@assign" : local.intermediate_retention_days_tag }, "tag_value" : { "@@assign" : coalesce(rule["intermediate_retention_days"], plan["intermediate_retention_days"], 7) }
          }
        } : {}
        ) 
      } },
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
    } }
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
