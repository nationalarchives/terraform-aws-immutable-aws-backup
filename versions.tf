terraform {
  required_version = ">= 1.9.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.6.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.4.0"
    }
  }
}
