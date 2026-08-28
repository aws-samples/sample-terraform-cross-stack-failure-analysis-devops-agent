terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50.0"
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
      "Stack"            = "data"
    }
  }
}
