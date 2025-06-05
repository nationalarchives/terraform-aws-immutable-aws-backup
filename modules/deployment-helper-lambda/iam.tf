module "lambda_role" {
  source = "../iam-role"

  name = "${var.lambda_function_name}-lambda"
  assume_role_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Effect = "Allow"
        Principal : {
          Service : "lambda.amazonaws.com"
        }
        Action : "sts:AssumeRole"
      }
    ]
  })

  inline_policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Effect : "Allow"
        Action : [
          "s3:ListBucket"
        ]
        Resource : "arn:aws:s3:::${var.terraform_state_bucket_name}"
      },
      {
        Effect : "Allow"
        Action : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource : "arn:aws:s3:::${var.terraform_state_bucket_name}/*"
      },
      {
        Effect : "Allow"
        Action : [
          "sts:AssumeRole"
        ]
        Resource : var.member_account_deployment_helper_role_arn_pattern,
        Condition : {
          StringEquals : {
            "aws:ResourceOrgID" : var.organization_id
          }
        }
      }
    ]
  })

  policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]
}
