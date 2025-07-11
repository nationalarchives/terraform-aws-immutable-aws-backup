resource "aws_sns_topic" "lambda_invoke" {
  region = var.region
  name   = var.lambda_function_name
}

resource "aws_sns_topic_policy" "lambda_invoke" {
  region = var.region
  arn    = aws_sns_topic.lambda_invoke.arn
  policy = jsonencode({
    Version : "2012-10-17"
    Statement : [
      {
        Effect : "Allow"
        Principal : {
          AWS : "*"
        },
        Action : "SNS:Publish"
        Resource : aws_sns_topic.lambda_invoke.arn,
        Condition : {
          StringEquals : {
            "aws:PrincipalOrgId" : var.current.organization_id
          },
          ArnLike : {
            "aws:PrincipalArn" : [
              "arn:${var.current.partition}:iam::*:role/stacksets-exec-*"
            ]
          }
        }
      }
    ]
  })
}
