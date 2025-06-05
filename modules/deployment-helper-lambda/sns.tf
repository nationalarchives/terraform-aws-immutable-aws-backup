resource "aws_sns_topic" "lambda_invoke" {
  name = var.lambda_function_name
}

resource "aws_sns_topic_policy" "lambda_invoke" {
  arn = aws_sns_topic.lambda_invoke.arn
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
            "aws:PrincipalOrgId" : var.organization_id
          },
          StringLike : {
            "aws:PrincipalArn" : [
              "arn:aws:iam::*:role/stacksets-exec-*"
            ]
          }
        }
      }
    ]
  })
}
