# Module Concept

[AWS Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/whatisbackup.html) is a fully-managed service that makes it easy to centralize and automate data protection across AWS services. AWS Backup allows the implementation of Backup Plans (Policies when applied to an AWS Organization) to manage the backing up of resources within AWS.

AWS Backup acts as a shim over thee existing AWS service APIs to orchestrate and manage backups. For example, backups of RDS databases utilise the existing snapshot mechanisms within RDS.

## What about Vault Lock?
Immutability within AWS Backup is achieved through the use of [Compliance mode](https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html#backup-vault-lock-modes) vault locking. However, whilst this prevents the recovery points within the vault from being deleted, it does not prevent the KMS Key used to encrypt these from being deleted. An attacker would only need to delete this KMS Key to make the data within the backups inaccessible.

Protecting a KMS Key is much more difficult. Although keys cannot be deleted immedietely, they can be scheduled for deletion with only 7 days grace. Keys can be protected through [Key Policies](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html), such as removing the ability to schedule key deletions or update the key policy, but this is a known issue within AWS with a well documented path to recover these abilities through opening a case with AWS Support.

AWS identified this issue and launched Logically Air Gapped (LAG) Vaults; amoung other features, these vaults re-encrypt their contents with an AWS Owned Key. But, not all AWS resource types are supported by LAG Vaults, creating a complex matrix of resources and vault types.

This module solves these issues by moving backups to a vault encrypted with an AWS Managed Key. Both AWS Managed and AWS Owned Keys cannot be deleted by principals within an AWS account. When the `use_logically_air_gapped_vault` option is enabled in a plan, only resources that are not supported by LAG Vaults are handled in this way, reducing the time to complexity and time to recover.
