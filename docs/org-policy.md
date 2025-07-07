# Organization Delegation Policy

The account to which you are deploying this module requires permission to [manage Backup Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_delegate_policies.html) through your Organization's delegation policy.

An example delegation policy is provided below, derived from [AWS guidelines](https://aws.amazon.com/blogs/storage/delegated-administrator-support-for-aws-backup). 

- In the console for your AWS management account, navigate to AWS Organizations -> Settings -> Delegated administrator for AWS Organizations -> Delegate

- Press Delegate to create delegation policy

- Copy and paste the contents below

- replace `${aws_backup_account_id}` with the AWS Account ID of your Backup account

- replace `${management_account_id}` with the AWS Account ID of your Management account

- replace `${org_id}` with your Organization ID

- replace `${root_id}` with your Organization Root ID

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
        "arn:aws:organizations::${management_account_id}:root/${org_id}/${root_id}"
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