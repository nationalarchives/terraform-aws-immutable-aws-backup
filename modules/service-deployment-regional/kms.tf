resource "aws_kms_replica_key" "key" {
  count = var.region != var.current_aws_region ? 1 : 0

  region          = var.region
  primary_key_arn = var.kms.primary_key_arn
  policy          = var.kms.kms_key_policy
}

resource "aws_kms_alias" "key" {
  count = var.region != var.current_aws_region ? 1 : 0

  region        = var.region
  name          = var.kms.kms_key_alias
  target_key_id = aws_kms_replica_key.key[0].key_id
}

locals {
  kms_key_arn = try(aws_kms_replica_key.key[0].arn, var.kms.primary_key_arn)
  kms_key_id  = try(aws_kms_replica_key.key[0].key_id, var.kms.kms_key_id)
}
