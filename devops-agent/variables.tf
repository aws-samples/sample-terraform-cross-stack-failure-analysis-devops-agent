variable "region" {
  description = "AWS region for supporting resources (Lambda, SSM, etc.)"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix used for tagging and resource names"
  type        = string
  default     = "cross-stack-demo"
}

variable "agent_space_name" {
  description = "Name for the DevOps Agent Space"
  type        = string
  default     = "cross-stack-failure-demo"
}

variable "alarms_sns_topic_arn" {
  description = "ARN of the SNS topic from the data-monitoring stack that alarm notifications are published to"
  type        = string
}

variable "webhook_url_param_name" {
  description = "SSM Parameter Store name for the DevOps Agent webhook URL (value set manually after generating in console)"
  type        = string
  default     = "/devops-agent/cross-stack-demo/webhook-url"
}

variable "hmac_secret_param_name" {
  description = "SSM Parameter Store name for the DevOps Agent HMAC signing secret (value set manually after generating in console)"
  type        = string
  default     = "/devops-agent/cross-stack-demo/hmac-secret"
}
