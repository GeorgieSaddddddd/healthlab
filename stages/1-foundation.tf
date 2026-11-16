# Stage 1 — foundation: Amplify app (reserves the web URL), S3, DynamoDB, SNS
# Expected: Plan: 8 to add

locals {
  app_origin = "https://main.${aws_amplify_app.web.default_domain}"
  app_url    = "${local.app_origin}/"
  origins    = [local.app_origin, "http://localhost:8000"] # localhost = test index.html on a laptop
}

# Amplify is created first because Cognito, CORS and email links all need its URL
resource "aws_amplify_app" "web" {
  name     = local.name
  platform = "WEB"
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.web.id
  branch_name = "main"
}

# Learner Lab's SCP denies s3:GetBucketObjectLockConfiguration, which the aws_s3_bucket
# resource needs on every read (provider v5 and v6) -> create/delete the bucket with the CLI.
# The settings below (public access block, lifecycle, CORS) are normal tofu resources.
resource "terraform_data" "uploads" {
  input = "${local.name}-uploads"

  provisioner "local-exec" {
    command = "aws s3api create-bucket --bucket ${self.input} --region us-east-1"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "aws s3 rb s3://${self.input} --force" # empties the bucket, then deletes it
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket                  = terraform_data.uploads.output
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "uploads" {
  bucket = terraform_data.uploads.output
  rule {
    id     = "delete-uploads-after-30-days"
    status = "Enabled"
    filter { prefix = "uploads/" }
    expiration { days = 30 }
  }
}

resource "aws_s3_bucket_cors_configuration" "uploads" {
  bucket = terraform_data.uploads.output
  cors_rule {
    allowed_methods = ["POST"] # browser uploads with a presigned POST
    allowed_origins = local.origins
    allowed_headers = ["*"]
  }
}

resource "aws_dynamodb_table" "reports" {
  name         = "${local.name}-reports"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"   # Cognito sub
  range_key    = "reportId" # time-prefixed => sorted by date
  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "reportId"
    type = "S"
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

output "app_url" {
  value = local.app_url
}

output "uploads_bucket" {
  value = terraform_data.uploads.output
}

output "reports_table" {
  value = aws_dynamodb_table.reports.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
