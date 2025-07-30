# Module Architecture

The module is designed to be deployed in a dedicated account within an AWS Organization, this account [must be delegated certain abilities for the module to function](usage.md).

![An AWS architecture diagram showing the module architecture. There are 2 AWS accounts, the Backup delegate account and the Workload accounts (of which there could be multiple). In the Backup delegate account are 3 Backup Vaults - LAG Vault, Intermediate Standard Vault, and Standard Vault -  there is also an EventBridge Event Bus. In the Workload account are resources to be backed up, these have an arrow directing backups in a Standard Vault within this account. From the Workload account's Standard Vault an arrow goes to the LAG and Intermediate Standard Vaults in the other account. The Intermediate Standard Vault then has an arrow to the Standard Vault in the Backup delegate account with a Step Function over it. An Event Bridge rule for Backup events in the Workload account forwards these to the Event Bus in the Backup delegate account.](assets/images/backup-architecture.png)

## Deployment to member accounts

Deployment to member accounts is orchestrated through [CloudFormation StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html). The module uses CloudFormation as it enables deployment to many AWS accounts without the need to configure and manage a Terraform provider for each account. StackSets work natively within AWS, reacting when accounts are moved between Organizations and Organizational Units to provision and destroy resources depending on their location within an Organization.

However, as CloudFormation is a declarative syntax for provisioning resources, even more so than Terraform, some of the member account deployment functionality has been implemented through [custom resources](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources.html) - AWS Lambda calling the AWS API or running Terraform itself. For example, creating the AWS Backup Service-linked IAM Role will only succeed if this role doesn't already exist; by using a custom Lambda function this error can be caught and ignored. Terraform is used to deploy the Backup Vaults within member accounts as it includes a `force_destroy` option that will empty a Vault before deleting it, whereas CloudFormation would fail to delete a Vault with contents.

![An AWS architecture diagram showing how Cloudformation and Lambda are used to deploy resources, has 6 steps. 1. The Organization Management Account delegates the Backup Delegate Account CloudFormation StackSet administration abilities. 2. The Backup Delegate Account creates a StackSet. 3. The StackSet creates Stacks in Workload accounts. 4. Cloudformation within the workload accounts publishes a message to an SNS topic in the Backup Delegate Account. 5. The Deployment Helper Lambda is invoked by SNS. 6. The Deployment Helper Lambda deploys resources into the Workload account.](assets/images/deployment-helper-lambda-architecture.png)

## Central account resources

- Deployment helper SNS topic
- Deployment helper Lambda function
- AWS Backup Service-linked IAM Role
- S3 Terraform state bucket for deployments to workload accounts

## Central account resources per deployment

- EventBridge Event Bus
- Backup Ingest Step Function
- Intermediate Backup Vault
- Standard Backup Vault
- LAG Backup Vault
- AWS Backup Service Role
- KMS Customer Managed Key
- CloudFormation StackSet
- Resource Access Manager (RAM) share

## Member account resources

- Backup Vault
- Restore Vault
- AWS Backup Service-linked IAM Role
- AWS Backup Service Role
- EventBridge Rule forwarding AWS Backup events
