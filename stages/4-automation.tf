# Stage 4 — automation: EventBridge rule runs the reminder Lambda every day
# Expected: Plan: 3 to add

resource "aws_cloudwatch_event_rule" "daily" {
  name                = "${local.name}-daily-reminder"
  schedule_expression = "cron(0 2 * * ? *)" # 02:00 UTC = 09:00 Bangkok
}

resource "aws_cloudwatch_event_target" "daily" {
  rule = aws_cloudwatch_event_rule.daily.name
  arn  = aws_lambda_function.fn["reminder"].arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn["reminder"].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily.arn
}
