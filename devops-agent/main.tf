############################################
# Data sources
############################################
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

############################################
# DevOps Agent Space (via awscc provider)
############################################
resource "awscc_devopsagent_agent_space" "this" {
  name = var.agent_space_name

  tags = [
    { key = "Project", value = var.project },
    { key = "ManagedBy", value = "terraform" },
  ]
}

############################################
# IAM Role for DevOps Agent
############################################
data "aws_iam_policy_document" "agent_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [awscc_devopsagent_agent_space.this.arn]
    }
  }
}

resource "aws_iam_role" "devops_agent" {
  name               = "${var.project}-devops-agent-role"
  assume_role_policy = data.aws_iam_policy_document.agent_assume_role.json

  tags = {
    Name = "${var.project}-devops-agent-role"
  }
}

# Attach the AWS managed policy for DevOps Agent access
resource "aws_iam_role_policy_attachment" "agent_managed_policy" {
  role       = aws_iam_role.devops_agent.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}

# Inline policy: allow DevOps Agent to create the Resource Explorer service-linked role
data "aws_iam_policy_document" "agent_slr" {
  statement {
    sid       = "AllowResourceExplorerSLR"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/resource-explorer-2.amazonaws.com/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["resource-explorer-2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "agent_slr" {
  name   = "${var.project}-agent-resource-explorer-slr"
  role   = aws_iam_role.devops_agent.id
  policy = data.aws_iam_policy_document.agent_slr.json
}

############################################
# Associate the AWS account with the Agent Space
############################################
resource "awscc_devopsagent_association" "account" {
  agent_space_id = awscc_devopsagent_agent_space.this.agent_space_id
  service_id     = "aws"

  configuration = {
    aws = {
      account_id        = local.account_id
      account_type      = "monitor"
      assumable_role_arn = aws_iam_role.devops_agent.arn
    }
  }
}

############################################
# SSM Parameters (placeholders — values set manually from console)
############################################
resource "aws_ssm_parameter" "webhook_url" {
  name        = var.webhook_url_param_name
  description = "DevOps Agent webhook URL — generate in Agent Space console and update this value"
  type        = "SecureString"
  value       = "PLACEHOLDER-generate-in-console"

  tags = {
    Name = "${var.project}-webhook-url"
  }

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "hmac_secret" {
  name        = var.hmac_secret_param_name
  description = "DevOps Agent HMAC signing secret — generate in Agent Space console and update this value"
  type        = "SecureString"
  value       = "PLACEHOLDER-generate-in-console"

  tags = {
    Name = "${var.project}-hmac-secret"
  }

  lifecycle {
    ignore_changes = [value]
  }
}

############################################
# Webhook Bridge Lambda
############################################
data "archive_file" "webhook_bridge_zip" {
  type        = "zip"
  source_dir  = "${path.module}/webhook-bridge"
  output_path = "${path.module}/build/webhook-bridge.zip"
}

data "aws_iam_policy_document" "bridge_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bridge_lambda" {
  name               = "${var.project}-webhook-bridge-role"
  assume_role_policy = data.aws_iam_policy_document.bridge_assume.json

  tags = {
    Name = "${var.project}-webhook-bridge-role"
  }
}

resource "aws_iam_role_policy_attachment" "bridge_basic" {
  role       = aws_iam_role.bridge_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Required for X-Ray Active tracing
resource "aws_iam_role_policy_attachment" "bridge_xray" {
  role       = aws_iam_role.bridge_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

data "aws_iam_policy_document" "bridge_ssm" {
  statement {
    sid     = "ReadWebhookParams"
    actions = ["ssm:GetParameter"]
    resources = [
      aws_ssm_parameter.webhook_url.arn,
      aws_ssm_parameter.hmac_secret.arn,
    ]
  }
}

resource "aws_iam_role_policy" "bridge_ssm" {
  name   = "${var.project}-bridge-ssm-read"
  role   = aws_iam_role.bridge_lambda.id
  policy = data.aws_iam_policy_document.bridge_ssm.json
}

resource "aws_cloudwatch_log_group" "bridge" {
  name              = "/aws/lambda/${var.project}-webhook-bridge"
  retention_in_days = 14
}

resource "aws_lambda_function" "webhook_bridge" {
  function_name = "${var.project}-webhook-bridge"
  role          = aws_iam_role.bridge_lambda.arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  timeout       = 30
  memory_size   = 128

  reserved_concurrent_executions = 10

  filename         = data.archive_file.webhook_bridge_zip.output_path
  source_code_hash = data.archive_file.webhook_bridge_zip.output_base64sha256

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      WEBHOOK_URL_PARAM = var.webhook_url_param_name
      HMAC_SECRET_PARAM = var.hmac_secret_param_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.bridge_basic,
    aws_iam_role_policy_attachment.bridge_xray,
    aws_cloudwatch_log_group.bridge,
  ]

  tags = {
    Name = "${var.project}-webhook-bridge"
  }
}

############################################
# SNS subscription: alarms topic → webhook bridge Lambda
############################################
resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook_bridge.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.alarms_sns_topic_arn
}

resource "aws_sns_topic_subscription" "bridge" {
  topic_arn = var.alarms_sns_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.webhook_bridge.arn
}
