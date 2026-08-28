variable "region" {
  description = "AWS region for the data + monitoring stack"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix used for tagging and resource names"
  type        = string
  default     = "cross-stack-demo"
}

variable "table_name" {
  description = "DynamoDB table name"
  type        = string
  default     = "cross-stack-demo-items"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function from the compute stack (used to wire the error-rate alarm). Must match the function name in stacks/compute."
  type        = string
  default     = "cross-stack-demo-api"
}

variable "alarm_email" {
  description = "Optional email for SNS alarm subscription. Leave empty to skip."
  type        = string
  default     = ""
}
