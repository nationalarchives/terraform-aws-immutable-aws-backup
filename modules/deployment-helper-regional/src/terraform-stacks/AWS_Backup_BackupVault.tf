terraform {
  required_version = ">= 1.11.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.14.1"
    }
  }
}

variable "AccessPolicy" {
  type    = string
  default = ""
}

variable "BackupVaultName" {
  type = string
}

variable "BackupVaultTags" {
  type    = map(string)
  default = {}
}

variable "EncryptionKeyArn" {
  type    = string
  default = null
}

variable "LockConfiguration" {
  type = map(any)
  /*
  {
    # ChangeableForDays = number
    MaxRetentionDays = number
    MinRetentionDays = number
  }
  */
  default = {}
}

variable "ForceDestroy" {
  type    = bool
  default = false
}

resource "aws_backup_vault" "this" {
  name          = var.BackupVaultName
  kms_key_arn   = var.EncryptionKeyArn
  tags          = var.BackupVaultTags
  force_destroy = var.ForceDestroy
}

resource "aws_backup_vault_policy" "this" {
  count             = length(var.AccessPolicy) > 0 ? 1 : 0
  backup_vault_name = aws_backup_vault.this.id
  policy            = var.AccessPolicy
}

resource "aws_backup_vault_lock_configuration" "this" {
  count               = length(var.LockConfiguration) > 0 ? 1 : 0
  backup_vault_name   = aws_backup_vault.this.id
  changeable_for_days = lookup(var.LockConfiguration, "ChangeableForDays", null)
  max_retention_days  = lookup(var.LockConfiguration, "MaxRetentionDays", null)
  min_retention_days  = lookup(var.LockConfiguration, "MinRetentionDays", null)
}
