output "lambda_role_arn" {
  value = module.lambda_role.role.arn

  # Important: Ensures that the CloudFormation -> SNS -> Lambda pipeline works during a destroy.
  depends_on = [
    aws_sns_topic_policy.lambda_invoke,
    aws_sns_topic_subscription.lambda
  ]
}

output "sns_topic" {
  value = aws_sns_topic.lambda_invoke

  # Important: Ensures that the CloudFormation -> SNS -> Lambda pipeline works during a destroy.
  depends_on = [
    aws_sns_topic_policy.lambda_invoke,
    aws_sns_topic_subscription.lambda
  ]
}
