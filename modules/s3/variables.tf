variable "central_account_resource_name_prefix" {
  description = "Central account resource name prefix, e.g. aws-backup-"

  validation {
    condition     = length(var.central_account_resource_name_prefix) <= 28
    error_message = "central_account_resource_name_prefix must be less than or equal to 28 characters"
  }
}

variable "kms_key_arn" {
  description = "ARN of KMS key for S3 bucket encryption, if omitted, S3 managed key will be used"
  default     = ""
}

variable "log_bucket" {
  description = "Enter name of log bucket to enable access logs"
  default     = ""
}

variable "force_destroy" {
  description = "destroy S3 bucket on Terraform destroy even with objects in bucket"
  default     = true
}

variable "object_ownership" {
  description = "manage S3 bucket ownership controls"
  default     = "BucketOwnerEnforced"
  validation {
    condition     = contains(["BucketOwnerPreferred", "ObjectWriter", "BucketOwnerEnforced"], var.object_ownership)
    error_message = "object_ownership must be one of BucketOwnerPreferred, ObjectWriter, or BucketOwnerEnforced."
  }
}

variable "block_public_acls" {
  default = true
}

variable "block_public_policy" {
  default = true
}

variable "ignore_public_acls" {
  default = true
}

variable "restrict_public_buckets" {
  default = true
}

variable "bpa_skip_destroy" {
  description = "Skip destroy of S3 block public access configuration"
  default     = true
}

variable "versioning" {
  description = "Enable versioning"
  default     = "Enabled"
  validation {
    condition     = contains(["Enabled", "Suspended", "Disabled"], var.versioning)
    error_message = "versioning must be one of Enabled, Suspended, or Disabled."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}