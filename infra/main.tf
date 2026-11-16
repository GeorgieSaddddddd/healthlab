# Stage 0 — base: providers, variables, shared names. No resources yet.
# Each stage adds one file from ../stages/ into this folder, then `tofu apply`. See ../README.md.
#
# Learner Lab cannot create IAM roles, so every Lambda uses the existing LabRole and
# the daily job uses an EventBridge rule (no role needed) instead of EventBridge Scheduler.

terraform {
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

variable "region" {
  default = "us-east-1"
}

variable "gemini_api_key" {
  type      = string
  sensitive = true # ponytail: still stored in Lambda env + tofu state; use SSM SecureString for production
}

variable "remind_days" {
  description = "Days before the re-test reminder; 0 = remind immediately (for testing)"
  default     = 90
}

provider "aws" {
  region = var.region
}

data "aws_iam_role" "lab" {
  name = "LabRole"
}

data "aws_caller_identity" "me" {}

locals {
  # account ID makes names (Cognito domain, bucket) globally unique with nothing to type
  name = "healthlab-${data.aws_caller_identity.me.account_id}"
}

output "name" {
  value = local.name
}
