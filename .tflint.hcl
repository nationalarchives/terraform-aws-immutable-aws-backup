plugin "aws" {
  enabled = true
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
  version = "0.40.0"

  rule "aws_iam_policy_document_gov_friendly_arns" {
    enabled = true
  }
  rule "aws_iam_policy_gov_friendly_arns" {
    enabled = true
  }
  rule "aws_iam_role_deprecated_policy_attributes" {
    enabled = true
  }
  rule "aws_iam_role_policy_gov_friendly_arns" {
    enabled = true
  }
}
