#
# Creates a service-linked role for AWS Backup if it does not already exist.
#

data "aws_iam_roles" "backup_service_linked_roles" {
  path_prefix = "/aws-service-role/backup.amazonaws.com/"
}

locals {
  potential_backup_service_linked_role_arn  = one(data.aws_iam_roles.backup_service_linked_roles.arns)
  potential_backup_service_linked_role_name = one(data.aws_iam_roles.backup_service_linked_roles.names)
}

data "aws_iam_role" "potential_backup_service_linked_role" {
  count = local.potential_backup_service_linked_role_arn == null ? 0 : 1
  name  = local.potential_backup_service_linked_role_name
}

resource "aws_iam_service_linked_role" "backup_service_linked_role" {
  count = try(
    data.aws_iam_role.potential_backup_service_linked_role[0].tags["terraform"] == "true" &&
    data.aws_iam_role.potential_backup_service_linked_role[0].tags["deployment_region"] == data.aws_region.current.region ? 1 : 0, 1
  )

  aws_service_name = "backup.amazonaws.com"
  description      = "Service-linked role for AWS Backup"

  tags = {
    "terraform"         = "true",
    "deployment_region" = data.aws_region.current.region,
  }
}

locals {
  backup_service_linked_role_arn = try(aws_iam_service_linked_role.backup_service_linked_role[0].arn, local.potential_backup_service_linked_role_arn)
}
