# Prerequisites

**It is strongly recommended that this module is deployed into a dedicated AWS Backup account within your AWS Organization.**

The module is designed to be deployed into a delegated administrator account within an AWS Organization, it assumes that these requirements are met when deploying:

- [All features are enabled](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_org_support-all-features.html) for your AWS Organization.
- Trusted access [with AWS Backup](https://docs.aws.amazon.com/organizations/latest/userguide/services-that-can-integrate-backup.html#integrate-enable-ta-backup) and [Resource Access Manager (RAM)](https://docs.aws.amazon.com/organizations/latest/userguide/services-that-can-integrate-ram.html#integrate-enable-ta-ram) is enabled on your Organization.
- [Backup Policies](https://docs.aws.amazon.com/organizations/latest/userguide/enable-policy-type.html) are enabled within your Organization.
- [Enable cross-account backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/create-cross-account-backup.html#prereq-cab) is turned on within your Organization.
- [AWS Backup cross-account monitoring](https://docs.aws.amazon.com/aws-backup/latest/devguide/manage-cross-account.html#enable-cross-account) is enabled within your Organization.
- The account you are deploying to has been [delegated to manage AWS Backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/manage-cross-account.html#backup-delegatedadmin).
- The account you are deploying to has been [delegated to manage CloudFormation StackSets](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/stacksets-orgs-delegated-admin.html).
- The account you are deploying to has permission to [manage Backup Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_delegate_policies.html), as detailed in [our example resource-based delegation policy](#example-organization-resource-based-delegation-policy).

## Example organization resource-based delegation policy

The account to which you are deploying this module requires permission to [manage Backup Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_delegate_policies.html) through your Organization's resource-based delegation policy.

An example resource-based delegation policy is provided below, derived from [AWS guidelines](https://aws.amazon.com/blogs/storage/delegated-administrator-support-for-aws-backup).

- In the console for your AWS management account, navigate to AWS Organizations -> Settings -> Delegated administrator for AWS Organizations -> Delegate.
- Press Delegate to create delegation policy.
- Copy and paste the contents below;
  - replace `${aws_backup_account_id}` with the AWS Account ID of your Backup account,
  - replace `${management_account_id}` with the AWS Account ID of your Management account,
  - replace `${org_id}` with your Organization ID.

<!-- prettier-ignore-start -->
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowBackupDelegateOrganizationsReadAndTag",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${aws_backup_account_id}:root"
      },
      "Action": [
        "organizations:Describe*",
        "organizations:List*",
        "organizations:TagResource",
        "organizations:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowBackupDelegatePolicyCreation",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${aws_backup_account_id}:root"
      },
      "Action": [
        "organizations:CreatePolicy"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "organizations:PolicyType": "BACKUP_POLICY"
        }
      }
    },
    {
      "Sid": "AllowBackupDelegatePolicyModification",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${aws_backup_account_id}:root"
      },
      "Action": [
        "organizations:DeletePolicy",
        "organizations:UpdatePolicy"
      ],
      "Resource": "arn:aws:organizations::${management_account_id}:policy/*/backup_policy/*",
      "Condition": {
        "StringEquals": {
          "organizations:PolicyType": "BACKUP_POLICY"
        }
      }
    },
    {
      "Sid": "AllowBackupDelegateToAttachDetachPoliciesWithinProjectScope",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${aws_backup_account_id}:root"
      },
      "Action": [
        "organizations:AttachPolicy",
        "organizations:DetachPolicy"
      ],
      "Resource": [
        "arn:aws:organizations::${management_account_id}:policy/*/backup_policy/*",
        "arn:aws:organizations::${management_account_id}:account/${org_id}/*",
        "arn:aws:organizations::${management_account_id}:ou/${org_id}/*",
        "arn:aws:organizations::${management_account_id}:root/${org_id}/*"
      ],
      "Condition": {
        "StringEquals": {
          "organizations:PolicyType": "BACKUP_POLICY"
        }
      }
    }
  ]
}
```
<!-- prettier-ignore-end -->
