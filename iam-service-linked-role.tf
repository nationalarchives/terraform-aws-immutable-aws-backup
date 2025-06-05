#
# Creates a service-linked role for AWS Backup if it does not already exist.
#

data "aws_iam_roles" "backup_service_linked_roles" {
  path_prefix = "/aws-service-role/backup.amazonaws.com/"
}

locals {
  potential_backup_service_linked_role_arn = one(data.aws_iam_roles.backup_service_linked_roles.arns)
}

resource "aws_iam_service_linked_role" "backup_service_linked_role" {
  count = local.potential_backup_service_linked_role_arn == null ? 1 : 0

  aws_service_name = "backup.amazonaws.com"
  description      = "Service-linked role for AWS Backup"
}

locals {
  backup_service_linked_role_arn = try(aws_iam_service_linked_role.backup_service_linked_role[0].arn, local.potential_backup_service_linked_role_arn)
}
