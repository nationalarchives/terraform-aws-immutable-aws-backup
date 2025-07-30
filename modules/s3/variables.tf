variable "bucket_prefix" {
  type        = string
  description = "S3 Terraform state bucket name prefix, e.g. aws-backup-tf-state-"

  validation {
    condition     = length(var.bucket_prefix) <= 37
    error_message = "bucket name prefix must be less than or equal to 37 characters"
  }
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of KMS key for S3 bucket encryption, if omitted, S3 managed key will be used"
  default     = ""
}

variable "log_bucket" {
  type        = string
  description = "Enter name of log bucket to enable access logs"
  default     = ""
}

variable "force_destroy" {
  description = "destroy S3 bucket on Terraform destroy even with objects in bucket"
  default     = true
}

variable "object_ownership" {
  type        = string
  description = "manage S3 bucket ownership controls"
  default     = "BucketOwnerEnforced"
  validation {
    condition     = contains(["BucketOwnerPreferred", "ObjectWriter", "BucketOwnerEnforced"], var.object_ownership)
    error_message = "object_ownership must be one of BucketOwnerPreferred, ObjectWriter, or BucketOwnerEnforced."
  }
}

variable "block_public_acls" {
  type        = bool
  description = "Block public ACLs on the S3 bucket"
  default     = true
}

variable "block_public_policy" {
  type        = bool
  description = "Block public bucket policies on the S3 bucket"
  default     = true
}

variable "ignore_public_acls" {
  type        = bool
  description = "Ignore public ACLs on the S3 bucket"
  default     = true
}

variable "restrict_public_buckets" {
  type        = bool
  description = "Restrict public bucket policies on the S3 bucket"
  default     = true
}

variable "bpa_skip_destroy" {
  type        = bool
  description = "Skip destroy of S3 block public access configuration"
  default     = true
}

variable "versioning" {
  type        = string
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