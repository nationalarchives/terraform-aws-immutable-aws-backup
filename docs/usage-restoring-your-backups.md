# Restoring from backups

Backups can be restored in the dedicated backup account or within the workload accounts targeted by the deployment. The module implements protections to prevent a backup from one deployment being restored to an account within a different deployment.

## Restoring from Logically Air Gapped Vaults

Logically Air Gapped Vaults allow restores to be performed directly within the workload accounts. The LAG Vault must first be shared with the workload account using AWS RAM, then a principal in the workload account can restore the backup using the AWS Backup console or CLI.

To enable AWS RAM sharing to the workload accounts, set [allow_backup_targets_to_restore](./usage-configuration.md#deployments_allow_backup_targets_to_restore) to `true` within the deployment configuration, then re-apply Terraform.

To restore a backup from a LAG Vault, follow the steps in [Restore a backup from a logically air-gapped vault](https://docs.aws.amazon.com/aws-backup/latest/devguide/logicallyairgappedvault.html#lag-restore) from the AWS documentation. The module deploys an IAM Role, `...-backup-service-restore-role`, to each workload account that can be passed to the restore job.

## Restoring from the Standard Backup Vaults

Backups held in the central `-intermediate-` or `-standard-` vaults need copying to a Backup Vault within the workload account before they can be restored. The module provides a Step Function to perform a series of copy operations to copy the backup to the workload account Backup Vaults. When the copy is complete, the backup will be available to restore using the AWS Backup console or CLI.

To start the copy action back to a workload account, start a new execution of the Restore Step Function for the deployment within the dedicated backup account; the Step Function expects an input with the following structure:

```json
{
  "destinationAccount": "222222222222",
  "recoveryPointArn": "arn:aws:backup:eu-west-1:111111111111:recovery-point:website-logs-20250708044140-61ebc5da",
  "sourceBackupVaultName": "aws-backup-my-deployment-standard-30-365"
}
```

The Step Function will copy the backup to the `-intermediate-` Backup Vault, re-encrypting the backup to use a customer managed KMS Key, then cross-account to the destination account's `-cmk` Backup Vault, and finally to the destination account's `-default` Backup Vault. The resultant backup will be encrypted with an AWS Managed KMS Key in the destination account. The backup may need copying once again within the destination account for the restored resource to use the correct encryption key for the workload.

Once the backup is within the destination account, the steps to restore in the AWS documentation can be followed, [Restore a backup by resource type](https://docs.aws.amazon.com/aws-backup/latest/devguide/restoring-a-backup.html). The module deploys an IAM Role, `...-backup-service-restore-role`, to each workload account that can be passed to the restore job.

## Restoring from the `-cmk` backup vault within a workload account

For resource types that are not "fully managed" by AWS Backup, backups taken into the `-cmk` Backup Vault will retain the encryption configuration of the source resource. This means that the backup can be restored directly by principals within the account, without needing to copy it to another Backup Vault. This only applies to backups that were written directly to this vault, not those copied to the account from the dedicated backup account.
