resource "aws_cloudwatch_log_group" "lambda" {
  region            = var.region
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 90
}

data "archive_file" "lambda_code" {
  type             = "zip"
  source_dir       = "${path.module}/src"
  excludes         = ["${path.module}/lambda.zip"]
  output_path      = "${path.module}/lambda.zip"
  output_file_mode = "0644"
}

resource "aws_lambda_function" "lambda" {
  region           = var.region
  function_name    = var.lambda_function_name
  role             = var.lambda_role_arn
  handler          = "main.handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_code.output_base64sha256
  filename         = data.archive_file.lambda_code.output_path
  timeout          = 900
  memory_size      = 1024

  environment {
    variables = {
      TERRAFORM_STATE_BUCKET : var.terraform_state_bucket_name
    }
  }

  ephemeral_storage {
    size = 1024
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

resource "aws_lambda_permission" "lambda" {
  region        = var.region
  statement_id  = "SNSInvokePermission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.lambda_invoke.arn
}

resource "aws_sns_topic_subscription" "lambda" {
  region    = var.region
  topic_arn = aws_sns_topic.lambda_invoke.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.lambda.arn

  depends_on = [aws_lambda_permission.lambda]
}
