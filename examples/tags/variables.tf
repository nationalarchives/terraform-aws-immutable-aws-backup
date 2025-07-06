variable "terraform_state_bucket" {
  description = "Terraform state bucket for backup deployments to workload accounts"
  default     = "my-terraform-state-bucket" # Change this to your actual bucket name
}