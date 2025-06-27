data "aws_partition" "current" {}

locals {
  partition_id = data.aws_partition.current.partition
}
