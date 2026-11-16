# Stage 2 — backend code: 4 Lambda functions (same app.py, different handler) + S3 trigger
# Expected: Plan: 10 to add

locals {
  functions = { analyzer = 180, api = 30, subscribe = 10, reminder = 60 } # handler => timeout (s)
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/app.py"
  output_path = "${path.module}/build/lambda.zip"
}

resource "aws_cloudwatch_log_group" "fn" {
  for_each          = local.functions
  name              = "/aws/lambda/${local.name}-${each.key}"
  retention_in_days = 7
}

resource "aws_lambda_function" "fn" {
  for_each         = local.functions
  function_name    = "${local.name}-${each.key}"
  handler          = "app.${each.key}"
  runtime          = "python3.12"
  timeout          = each.value
  memory_size      = 256
  role             = data.aws_iam_role.lab.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  environment {
    variables = {
      TABLE          = aws_dynamodb_table.reports.name
      BUCKET         = terraform_data.uploads.output
      TOPIC_ARN      = aws_sns_topic.alerts.arn
      GEMINI_API_KEY = var.gemini_api_key
      APP_URL        = local.app_url
      REMIND_DAYS    = tostring(var.remind_days)
    }
  }
  depends_on = [aws_cloudwatch_log_group.fn]
}

resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn["analyzer"].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${terraform_data.uploads.output}"
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket = terraform_data.uploads.output
  lambda_function {
    lambda_function_arn = aws_lambda_function.fn["analyzer"].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/" # analyzer never writes here => no recursive loop
  }
  depends_on = [aws_lambda_permission.s3]
}
