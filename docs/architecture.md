# Module Architecture

The module is designed to be deployed in a dedicated account within an AWS Organization, this account [must be delegated certain abilities for the module to function](usage-prerequisites.md).

One call of this module can deploy multiple instances of AWS Backup, each with a different configuration and to different Organizational Units; we call each of these a "deployment". Deployments act as a **security boundary** between instances; accounts targetted by one deployment cannot influence the backups of another deployment. The diagram below shows the architecture of a single deployment.

![An AWS architecture diagram showing the architecture of a deployment. There are 2 AWS accounts, the Backup delegate account and the Workload accounts (of which there could be multiple). In the Backup delegate account are 3 Backup Vaults - LAG Vault, Intermediate Standard Vault, and Standard Vault -  there is also an EventBridge Event Bus. In the Workload account are resources to be backed up, these have an arrow directing backups in a Standard Vault within this account. From the Workload account's Standard Vault an arrow goes to the LAG and Intermediate Standard Vaults in the other account. The Intermediate Standard Vault then has an arrow to the Standard Vault in the Backup delegate account with a Step Function over it. An Event Bridge rule for Backup events in the Workload account forwards these to the Event Bus in the Backup delegate account.](assets/images/backup-deployment-architecture.png)

Each deployment orchestrates the creation of resources in both the Backup account and the Workload accounts. Resources created in the Backup account are:

- 3x Backup Vaults - a Logically Air Gapped (LAG) Vault, an Intermediate Standard Vault, and a Standard Vault.
- An IAM Service Role for AWS Backup.
- An EventBridge Event Bus to receive AWS Backup events from the Workload accounts.
- An EventBridge Rule to forward AWS Backup events from the default bus to the deployment's Event Bus.
- A Step Function to copy backups from the Intermediate Standard Vault to the Standard Vault and update the lifecycle of backups that have been copied.
- A CloudFormation StackSet to deploy resources in the workload accounts.
- A KMS Customer Managed Key to encrypt backups in the Intermediate Vault and workload account vaults.
- A Resource Access Manager (RAM) Share to share the Logically Air Gapped (LAG) Vault with the Workload accounts for recovery.
- A Step Function to manage the copying of backups from the Standard Vault back to workload accounts for recovery.

## Resources in workload accounts

Each deployment orchestrates the creation of resources in workload accounts through [CloudFormation StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html). The module uses CloudFormation as it enables deployment to many AWS accounts without the need to configure and manage a Terraform provider for each account. StackSets work natively within AWS, reacting when accounts are moved between Organizations and Organizational Units to provision and destroy resources depending on their location within an Organization.

However, as CloudFormation is a declarative syntax for provisioning resources, even more so than Terraform, some of the workload account deployment functionality has been implemented through [custom resources](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/template-custom-resources.html) - an AWS Lambda calling the AWS API or running Terraform itself. For example, creating the AWS Backup Service-linked IAM Role will only succeed if this role doesn't already exist; by using a custom Lambda function this error can be caught and ignored. Terraform is used to deploy the Backup Vaults within workload accounts as it includes a `force_destroy` option that will empty a Vault before deleting it, whereas CloudFormation would fail to delete a Vault with content.

![An AWS architecture diagram showing how CloudFormation and Lambda are used to deploy resources, has 6 steps. 1. The Organization Management Account delegates the Backup Delegate Account CloudFormation StackSet administration abilities. 2. Terraform running in the Backup Delegate Account creates a StackSet. 3. The StackSet creates Stacks in workload accounts. 4. Cloudformation within the workload accounts publishes a message to an SNS topic in the Backup Delegate Account. 5. The Deployment Helper Lambda is invoked by SNS. 6. The Deployment Helper Lambda deploys resources into the Workload account.](assets/images/deployment-helper-lambda-architecture.png)

The "Deployment Helper" Lambda Function is deployed once in the dedicated Backup account. It is invoked by an SNS topic in the Backup account which recieves messages from CloudFormation stacks within the workload accounts. The Lambda function then deploys resources into the workload accounts. The resources created to support this are:

- An SNS topic to receive messages from CloudFormation stacks in workload accounts.
- An S3 Terraform state bucket, if not passed in as a variable.
- A Lambda function to deploy resources in workload accounts.
- An execution IAM Role for the Lambda Function.
- A CloudWatch Log Group for the Lambda Function.

Within each workload account, for each deployment, the following resources are created:

- Backup Vault
- Restore Vault
- AWS Backup Service-linked IAM Role
- AWS Backup Service Role
- EventBridge Rule forwarding AWS Backup events
