output "agent_space_arn" {
  description = "ARN of the DevOps Agent Space"
  value       = awscc_devopsagent_agent_space.this.arn
}

output "agent_space_id" {
  description = "ID of the DevOps Agent Space"
  value       = awscc_devopsagent_agent_space.this.agent_space_id
}

output "agent_iam_role_arn" {
  description = "IAM role ARN that DevOps Agent assumes"
  value       = aws_iam_role.devops_agent.arn
}

output "webhook_bridge_function_name" {
  description = "Webhook bridge Lambda function name"
  value       = aws_lambda_function.webhook_bridge.function_name
}

output "webhook_url_param" {
  description = "SSM parameter name for the webhook URL (update value via console)"
  value       = aws_ssm_parameter.webhook_url.name
}

output "hmac_secret_param" {
  description = "SSM parameter name for the HMAC secret (update value via console)"
  value       = aws_ssm_parameter.hmac_secret.name
}
