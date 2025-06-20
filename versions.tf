terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.99.1" # temporary change the version is actually "~> 5.100.0" 
    }
  }
}
