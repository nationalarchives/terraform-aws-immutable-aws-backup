output "lambda_role" {
  value = module.lambda_role.role

  # Important: Ensures that the CloudFormation -> SNS -> Lambda pipeline works during a destroy.
  depends_on = [module.deployment_helper_regional]
}

output "sns_topic" {
  value = values(module.deployment_helper_regional)[0].sns_topic

  # Important: Ensures that the CloudFormation -> SNS -> Lambda pipeline works during a destroy.
  depends_on = [module.deployment_helper_regional]
}
