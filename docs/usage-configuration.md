# Configuration

The module is designed to be deployed only once per Organization, it can be deployed multiple times as long as [`central_account_resource_name_prefix`](#inputs_central_account_resource_name_prefix) is unique to each module call. Within the configuration of the module you can define multiple deployments to target areas of your organization with tailored backup plans.

## Inputs

<!-- prettier-ignore-start -->
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| <a name="inputs_central_account_resource_name_prefix"></a> [central\_account\_resource\_name\_prefix](#inputs\_central\_account\_resource\_name\_prefix) | Prefix to be used for resource names in the central account. | `string` |  | yes |
| <a name="inputs_deployments"></a> [deployments](#inputs\_deployments) | A map of deployments, see [Deployments](#deployments) | `map(object)` |  | yes |
| <a name="inputs_member_account_resource_name_prefix"></a> [member\_account\_resource\_name\_prefix](#inputs\_member\_account\_resource\_name\_prefix) | Prefix to be used for resource names in member accounts. | `string` |  | yes |
| <a name="inputs_terraform_state_bucket_name"></a> [terraform\_state\_bucket\_name](#inputs\_terraform\_state\_bucket\_name) | Name of the S3 bucket used for storing Terraform state files for resources in workload accounts. If not specified, an S3 bucket will be created in the central account. | `string` |  | no |
<!-- prettier-ignore-end -->

### Deployments

A deployment is an instance of the backup solution. Within the deployment account it creates a single set of resources (Backup Vaults, KMS Key, CloudFormation StackSet, etc.) that can then be used by multiple workload accounts. Deployments create a **security boundary** for your backups. Deployments are passed to the module as a map, the key value for each deployment is used to generate unique resource names within the deployment account and workload accounts.

<!-- prettier-ignore-start -->
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| <a name="deployments_admin_role_names"></a> [admin\_role\_names](#deployments\_admin\_role\_names) | A list of role names that will have administrator abilities in member accounts. For example, administering the Backup Vaults. | `list(string)` | `[]` | no |
| <a name="deployments_allow_backup_targets_to_restore"></a> [allow\_backup\_targets\_to\_restore](#deployments\_allow\_backup\_targets\_to\_restore) | Allow restores within the `backup_targets` workload accounts. This will share the LAG Vault back to workload accounts through AWS RAM. | `bool` | `false` | no |
| <a name="deployments_backup_tag_key"></a> [backup\_tag\_key](#deployments\_backup\_tag\_key) | The tag key to query when `require_plan_name_resource_tag` is enabled within a plan. | `string` | `null` | no |
| <a name="deployments_backup_targets"></a> [backup\_targets](#deployments\_backup\_targets) | A list of Organizational Unit IDs to deploy the backup solution to. The module will deploy to all accounts within these OUs. | `list(string)` |  | yes |
| <a name="deployments_max_retention_days"></a> [max\_retention\_days](#deployments\_max\_retention\_days) | The maximum retention to configure on the Backup Vaults. Required when a plan is using a LAG Vault. | `number` | `null` | no |
| <a name="deployments_min_retention_days"></a> [min\_retention\_days](#deployments\_min\_retention\_days) | The minimum retention to configure on the Backup Vaults. Required when a plan is using a LAG Vault. | `number` | `null` | no |
| <a name="deployments_plans"></a> [plans](#deployments\_plans) | A map of backup plans to implement, see [Plans](#plans). | `map(object)` |  | yes |
| <a name="deployments_retained_vaults"></a> [retained_vaults](#deployments\_retained\_vaults) | A list of previously deployed Backup Vault configurations. This is used to retain Vaults that were previously configured and are now locked, preventing deletion. This is useful when changing the configuration of a deployment, such as changing the minimum or maximum retention days. | `list(object({ min_retention_days = number, max_retention_days = number, use_logically_air_gapped_vault = optional(bool, false) }))` | `[]` | no |
<!-- prettier-ignore-end -->

### Plans

A plan defines a selection of resources and a list of rules (when your backups should be taken) for AWS Backup to orchestrate. This module generates AWS Backup Plans based upon the configuration made here; the module implements additional functionality to simplify the configuration of AWS Backup and implement AWS guidance. Plans are passed to the module as a map, the key value for each plan is used to identify the plan and filter by resource tag when `require_plan_name_resource_tag` is enabled.

<!-- prettier-ignore-start -->
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| <a name="plans_complete_backup_window_minutes"></a> [complete\_backup\_window\_minutes](#plans\_complete\_backup\_window\_minutes) | Number of minutes after a backup job is successfully started before it must be completed or it will be canceled by AWS Backup. | `number` | `null` | no |
| <a name="plans_continuous_backup_schedule_expression"></a> [continuous\_backup\_schedule\_expression](#plans\_continuous\_backup\_schedule\_expression) | A cron expression for when to create [Continuous Backups](https://docs.aws.amazon.com/aws-backup/latest/devguide/point-in-time-recovery.html) of supported and enabled resources. It is recommended to set this outside of the backup windows defined in your rules and to run it regularly. | `string` | `"cron(0 0 ? * * *)"` | no |
| <a name="plans_create_continuous_backups"></a> [create\_continuous\_backups](#plans\_create\_continuous\_backups) | Create continuous backups for resources that support it to enable point in time recovery within the same account. These backups are not copied to the immutable backup vaults.<br/><br/>Supported resource types: RDS database instances, SAP HANA, S3. | `bool` | `false` | no |
| <a name="plans_intermediate_retention_days"></a> [intermediate\_retention\_days](#plans\_intermediate\_retention\_days) | The number of days to retain backups in the Intermediate Vault once copied to the Immutable Vault. Persisting backups in this vault can reduce copy latency through incremental backups. If not set will use the rule's `delete_after_days` configuration or 7 days if null. Can be overridden by setting on the rule. | `number` | Rule's `delete_after_days` or `7` | no |
| <a name="plans_local_retention_days"></a> [local\_retention\_days](#plans\_local\_retention\_days) | The number of days to retain backups in the workload account vaults once copied to the Intermediate or LAG vaults. Persisting backups in this vault can reduce backup latency through incremental backups. If not set will use the rule's `delete_after_days` configuration. Can be overridden by setting on the rule. This does not affect Continuous Backups. | `number` | Rule's `delete_after_days` | no |
| <a name="plans_require_plan_name_resource_tag"></a> [require\_plan\_name\_resource\_tag](#plans\_require\_plan\_name\_resource\_tag) | Only backup resources that have a resource tag with key [`backup_tag_key`](#deployments_backup_tag_key) and value matching the plan name. | `bool` | `true` | no |
| <a name="plans_snapshot_from_continuous_backups"></a> [snapshot\_from\_continuous\_backups](#plans\_snapshot\_from\_continuous\_backups) | Create continuous backups for resources that support it and then generate snapshot backups from these. Recommended by AWS to reduce cost.<br/><br/>Supported resource types: S3. | `bool` | `true` | no |
| <a name="plans_start_backup_window_minutes"></a> [start\_backup\_window\_minutes](#plans\_start\_backup\_window\_minutes) | Number of minutes to wait for a backup job to start before cancelling it. If this value is included, it must be at least 60 minutes to avoid errors. | `number` | `null` | no |
| <a name="plans_use_logically_air_gapped_vault"></a> [use\_logically\_air\_gapped\_vault](#plans\_use\_logically\_air\_gapped\_vault) | Copy backups to a Logically Air Gapped Vault for supported resource types. Logically Air Gapped Vaults enable faster recovery as backups can be restored cross-account. | `bool` | `false` | no |
| <a name="plans_rules"></a> [rules](#plans\_rules) | A list of backup rules to implement, defining when backups should be taken. Where rules have overlapping start windows, the rule with the greatest `delete_after_days` value will run. See [Rules](#rules). | `list` |  | yes |
<!-- prettier-ignore-end -->

### Rules

A rule defines when backups should be taken and how long they should be kept for. Where rules within a plan have overlapping start windows, the rule with the greatest `delete_after_days` value will run.

<!-- prettier-ignore-start -->
| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| <a name="rules_complete_backup_window_minutes"></a> [complete\_backup\_window\_minutes](#rules\_complete\_backup\_window\_minutes) | Number of minutes after a backup job is successfully started before it must be completed or it will be canceled by AWS Backup. Overrides the [value set on the plan](#plans\_complete\_backup\_window\_minutes). | `number` | `null` | no |
| <a name="rules_delete_after_days"></a> [delete\_after\_days](#rules\_delete\_after\_days) | The number of days a backup should be retained for. Required when the plan is using a LAG Vault. | `number` | `null` | no |
| <a name="rules_intermediate_retention_days"></a> [intermediate\_retention\_days](#rules\_intermediate\_retention\_days) | The number of days to retain backups in the Intermediate Vault once copied to the Immutable Vault. Overrides the [value set on the plan](#plans\_intermediate\_retention\_days). | `number` | `null` | no |
| <a name="rules_local_retention_days"></a> [local\_retention\_days](#rules\_local\_retention\_days) | The number of days to retain backups in the workload account vaults once copied to the Intermediate or LAG vaults. Overrides the [value set on the plan](#plans\_local\_retention\_days). | `number` | `null` | no |
| <a name="rules_name"></a> [name](#rules\_name) | A friendly name for the rule. | `string` | Rule's index number | no |
| <a name="rules_schedule_expression"></a> [schedule\_expression](#rules\_schedule\_expression) | A cron expression for when to start the backup window. | `string` |  | yes |
| <a name="rules_start_backup_window_minutes"></a> [start\_backup\_window\_minutes](#rules\_start\_backup\_window\_minutes) | Number of minutes to wait for a backup job to start before cancelling it. If this value is included, it must be at least 60 minutes to avoid errors. Overrides the [value set on the plan](#plans\_start\_backup\_window\_minutes). | `number` | `null` | no |
<!-- prettier-ignore-end -->
