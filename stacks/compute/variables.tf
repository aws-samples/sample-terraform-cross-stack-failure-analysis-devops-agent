variable "region" {
  description = "AWS region for the compute stack"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix used for tagging and resource names"
  type        = string
  default     = "cross-stack-demo"
}

variable "function_name" {
  description = "Lambda function name. Must match data-monitoring var.lambda_function_name so the error alarm is wired correctly."
  type        = string
  default     = "cross-stack-demo-api"
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout (seconds). Kept high so timeouts are clearly visible in logs when network path is broken."
  type        = number
  default     = 30
}

variable "tf_state_bucket" {
  description = "S3 bucket holding remote state files for the other stacks"
  type        = string
}

variable "tf_state_region" {
  description = "Region of the remote state bucket"
  type        = string
  default     = "us-east-1"
}

variable "networking_state_key" {
  description = "S3 key for the networking stack's state file"
  type        = string
  default     = "networking/terraform.tfstate"
}

variable "data_state_key" {
  description = "S3 key for the data-monitoring stack's state file"
  type        = string
  default     = "data/terraform.tfstate"
}
