output "lambda_role_arn" {
  value = module.lambda_role.role.arn
}

output "sns_topic" {
  value = aws_sns_topic.lambda_invoke
}
