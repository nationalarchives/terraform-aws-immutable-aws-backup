variable "assume_role_policy" {
  description = "The assume role policy document for the IAM role."
  type        = string
}

variable "inline_policy" {
  description = "The inline policy to attach to the IAM role."
  type        = string
  default     = ""
}

variable "name" {
  description = "The name of the IAM role to create."
  type        = string
}

variable "policy_arns" {
  description = "List of managed policy ARNs to attach to the IAM role."
  type        = list(string)
  default     = []
}
