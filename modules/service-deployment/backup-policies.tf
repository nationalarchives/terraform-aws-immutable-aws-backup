
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

  plans = merge(
    { for k, v in var.plans : "${k}-to-standard" => merge(v, { lag_plan : false, tag_value : k }) },
    local.create_lag_resources ? { for k, v in var.plans : "${k}-to-lag" => merge(v, { lag_plan : true, tag_value : k }) if v["use_logically_air_gapped_vault"] } : {}
  )

  policy_content = jsonencode({
    "plans" : { for plan_name, plan in local.plans : plan_name => {
      "regions" : { "@@assign" : [data.aws_region.current.id] },
      "rules" : { for rule_idx, rule in plan["rules"] : coalesce(rule["name"], rule_idx) => {
        "schedule_expression" : { "@@assign" : rule["schedule_expression"] },
        "target_backup_vault_name" : { "@@assign" : local.member_account_backup_vault_name },
        "enable_continuous_backup" : { "@@assign" : true },
        "start_backup_window_minutes" : { "@@assign" : 60 },
        "lifecycle" : {
          "delete_after_days" : { "@@assign" : 35 }
        },
        "copy_actions" : {
          "${plan["lag_plan"] ? local.current_lag_vault.arn : aws_backup_vault.intermediate.arn}" : {
            "target_backup_vault_arn" : { "@@assign" : plan["lag_plan"] ? local.current_lag_vault.arn : aws_backup_vault.intermediate.arn }
            "lifecycle" : {
              "delete_after_days" : { "@@assign" : plan["lag_plan"] ? rule["delete_after_days"] : 3 }
            }
          }
        },
        "recovery_point_tags" : plan["lag_plan"] ? {} : {
          "${local.delete_after_days_tag}" : {
            "tag_key" : {
              "@@assign" : local.delete_after_days_tag
            },
            "tag_value" : {
              "@@assign" : rule["delete_after_days"]
            }
          }
        }
      } },
      "selections" : {
        "resources" : {
          "${plan["require_plan_name_resource_tag"] ? "supported-resources-with-tag" : "all-supported-resources"}" : {
            "iam_role_arn" : { "@@assign" : "arn:aws:iam::$account:role/${local.member_account_backup_service_role_name}" },
            "resource_types" : { "@@assign" : !plan["use_logically_air_gapped_vault"] ? ["*"] : (plan["lag_plan"] ? local.resource_types_with_lag_support : local.resource_types_without_lag_support) },
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
  name        = var.service_name
  description = ""
  type        = "BACKUP_POLICY"
  content     = local.policy_content
}

resource "aws_organizations_policy_attachment" "backup_policy" {
  for_each = toset(var.deployment_targets)

  policy_id = aws_organizations_policy.backup_policy.id
  target_id = each.key
}
