# Backing up your resources

This document provides guidance on how to back up resources using this Terraform module. It will not repeat the [documentation provided by AWS Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/creating-a-backup.html), but will instead focus on the specific requirements and configurations needed for this module to work as expected.

## DynamoDB

[AWS Backup advanced features for DynamoDB](https://docs.aws.amazon.com/aws-backup/latest/devguide/advanced-ddb-backup.html) must be enabled within the workload accounts.

## KMS Encryption of resources

### AWS Managed KMS Keys

Immediate backups of resource types that are not "fully managed" by AWS Backup within the will retain the encryption configuration of the source resource, when backups are copied this will change to the encryption key of the destination Backup Vault. Backups of resources that are encrypted with an AWS managed KMS Key - a key with an alias starting `aws/` - [cannot be copied cross-account](https://docs.aws.amazon.com/aws-backup/latest/devguide/encryption.html#copy-encryption) so will fail to copy to the central account Backup Vault to be held immutably.

### Customer Managed KMS Keys

Backups of resource types that are "fully managed" by AWS Backup use the encryption key of the Backup Vault they are stored in. As the re-encryption happens during the Backup Job, the source encryption must allow the deployment's Backup Service Role within the same account to decrypt the data.

Backups of resource types that are not "fully managed" by AWS Backup within the workload accounts will retain the encryption configuration of the source resource until they are copied to another Backup Vault. To ensure that backups can be copied to the central account Backup Vault, the source KMS Key must allow the deployment's Backup Service Role and the central Backup accounts Service-linked Role to to decrypt the data.

Ensure that the statements below are included within the Key Policy of the customer managed KMS Key used to encrypt the source resources, these have been derived from [AWS Guidelines](https://repost.aws/knowledge-center/backup-troubleshoot-cross-account-copy).

```json
{
    "Version": "2012-10-17",
    "Statement": [
        ...
        {
      "Sid": "Allow AWS Backup to use the key for backup and cross-account copy",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::${WorkloadAccountID}:role/${DeploymentBackupServiceRoleName}",
          "arn:aws:iam::${CentralBackupAccountID}:role/aws-service-role/backup.amazonaws.com/AWSServiceRoleForBackup"
        ]
      },
      "Action": [
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Allow AWS Backup to manage grants for backup and cross-account copy",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::${WorkloadAccountID}:role/${DeploymentBackupServiceRoleName}",
          "arn:aws:iam::${CentralBackupAccountID}:role/aws-service-role/backup.amazonaws.com/AWSServiceRoleForBackup"
        ]
      },
      "Action": [
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant"
      ],
      "Resource": "*",
      "Condition": {
        "Bool": {
          "kms:GrantIsForAWSResource": "true"
        }
      }
    }
    ]
}
```

## S3

S3 is "fully managed" by AWS Backup, so only the deployment's Backup Service Role within the same account needs access to the data.

When `create_continuous_backups` or `snapshot_from_continuous_backups` is enabled on a plan targetting the bucket, a continuous backup will be created in the workload account Backup Vault. Snapshots will then be taken from the continuous backup and copied to the central account Backup Vault, in line with [AWS best practice](https://docs.aws.amazon.com/aws-backup/latest/devguide/s3-backups.html#bestpractices-costoptimization).

To ensure your objects are backed up, see the [prerequisites from AWS](https://docs.aws.amazon.com/aws-backup/latest/devguide/s3-backups.html#s3-backup-prerequisites).
