output "role" {
  description = "The IAM role created by this module."
  value       = aws_iam_role.this

  #Important: Ensures that the policies stay on the role until the role can be deleted.
  depends_on = [
    aws_iam_role_policy.this,
    aws_iam_role_policy_attachment.this
  ]
}
