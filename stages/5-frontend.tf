# Stage 5 — frontend: fill API/Cognito values into index.html, zip, deploy to Amplify
# Expected: Plan: 1 to add   (needs bash + aws cli => run in CloudShell)

data "archive_file" "web" {
  type        = "zip"
  output_path = "${path.module}/build/web.zip"
  source {
    filename = "index.html"
    content = replace(replace(replace(file("${path.module}/../web/index.html"),
      "__API_URL__", aws_apigatewayv2_api.api.api_endpoint),
      "__COGNITO_DOMAIN__", local.cognito_url),
    "__CLIENT_ID__", aws_cognito_user_pool_client.web.id)
  }
}

resource "terraform_data" "deploy_web" {
  triggers_replace = [data.archive_file.web.output_md5] # redeploys whenever index.html changes
  depends_on       = [aws_amplify_branch.main]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      read -r JOB URL < <(aws amplify create-deployment --region ${var.region} \
        --app-id ${aws_amplify_app.web.id} --branch-name main \
        --query '[jobId,zipUploadUrl]' --output text)
      curl -sSf -H 'Content-Type: application/zip' --upload-file '${data.archive_file.web.output_path}' "$URL"
      aws amplify start-deployment --region ${var.region} \
        --app-id ${aws_amplify_app.web.id} --branch-name main --job-id "$JOB" > /dev/null
      echo "Amplify deployment job $JOB started"
    EOT
  }
}
