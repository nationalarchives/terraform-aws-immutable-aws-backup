#
# Creates a service-linked role for AWS Backup if it does not already exist.
#

data "aws_iam_roles" "backup_service_linked_roles" {
  path_prefix = "/aws-service-role/backup.amazonaws.com/"
}

locals {
  deployment_identifier = trim(var.central_account_resource_name_prefix, "-/")

  potential_backup_service_linked_role_arn  = one(data.aws_iam_roles.backup_service_linked_roles.arns)
  potential_backup_service_linked_role_name = one(data.aws_iam_roles.backup_service_linked_roles.names)
}

data "aws_iam_role" "potential_backup_service_linked_role" {
  count = local.potential_backup_service_linked_role_name == null ? 0 : 1

  name = local.potential_backup_service_linked_role_name
}

resource "aws_iam_service_linked_role" "backup_service_linked_role" {
  count = try(
    lookup(data.aws_iam_role.potential_backup_service_linked_role[0].tags, "terraform", null) == "true" &&
    lookup(data.aws_iam_role.potential_backup_service_linked_role[0].tags, "deployment_region", null) == local.region ? 1 : 0, 1
  )

  aws_service_name = "backup.amazonaws.com"
  description      = "Service-linked role for AWS Backup"

  tags = {
    "terraform"             = "true",
    "deployment_region"     = local.region,
    "deployment_identifier" = local.deployment_identifier
  }
}

locals {
  backup_service_linked_role_arn = try(aws_iam_service_linked_role.backup_service_linked_role[0].arn, local.potential_backup_service_linked_role_arn)
}
