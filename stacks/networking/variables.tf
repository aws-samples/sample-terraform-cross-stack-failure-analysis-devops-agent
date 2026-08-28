variable "region" {
  description = "AWS region for the networking stack (must match the region your VPC/AZs live in)"
  type        = string
}

variable "project" {
  description = "Project name prefix used for tagging and resource names"
  type        = string
  default     = "cross-stack-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Pick a /16 that does not overlap any existing VPCs or on-prem ranges you peer with."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.42.0.0/16."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets, one per AZ. Must be inside vpc_cidr and the same length as var.azs."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "Provide at least two private subnet CIDRs (Lambda VPC config requires multi-AZ for HA)."
  }
}

variable "azs" {
  description = "Availability zones to place private subnets in. Must exist in var.region and align 1:1 with var.private_subnet_cidrs."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Provide at least two AZs."
  }
}

variable "restrict_egress" {
  description = "When true, restricts Lambda SG egress to VPC CIDR only (simulates the security-audit breaking change). When false, allows traffic to the DynamoDB VPC endpoint prefix list."
  type        = bool
  default     = false
}
