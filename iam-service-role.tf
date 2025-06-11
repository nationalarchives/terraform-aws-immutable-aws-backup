#
# Creates a service role for AWS Backup.
#

module "backup_service_role" {
  source = "./modules/iam-role"

  name = join("", [var.central_account_resource_name_prefix, "backup-service-role"])
  assume_role_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Effect = "Allow",
        Principal : {
          Service : "backup.amazonaws.com"
        },
        Action : "sts:AssumeRole",
        Condition : {
          StringEquals : {
            "aws:SourceAccount" : local.account_id
          }
        }
      }
    ]
  })
  policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
  ]
}
