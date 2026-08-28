terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.66.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      "devops-agent"     = "cross-stack-demo"
      "devops-agent-app" = "cross-stack-failure-demo"
      "Environment"      = "demo"
      "ManagedBy"        = "terraform"
      "Stack"            = "devops-agent"
    }
  }
}

# DevOps Agent resources are only available in us-east-1
provider "awscc" {
  region = "us-east-1"
}
