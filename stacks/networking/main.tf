############################################
# VPC
############################################
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-vpc"
  }

  lifecycle {
    precondition {
      condition     = length(var.private_subnet_cidrs) == length(var.azs)
      error_message = "private_subnet_cidrs and azs must be the same length (one subnet per AZ)."
    }
  }
}

############################################
# Private subnets (no NAT — Lambda reaches DynamoDB via Gateway VPC endpoint)
############################################
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project}-private-${var.azs[count.index]}"
    Tier = "private"
  }
}

############################################
# Private route table (one shared) — DynamoDB endpoint will be associated here
############################################
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

############################################
# DynamoDB Gateway VPC endpoint
############################################
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.project}-dynamodb-vpce"
  }
}

############################################
# VPC Flow Logs — helps DevOps Agent diagnose network-layer issues
############################################
resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  iam_role_arn         = aws_iam_role.flow_log.arn
  log_destination      = aws_cloudwatch_log_group.flow_log.arn
  log_destination_type = "cloud-watch-logs"

  tags = {
    Name = "${var.project}-vpc-flow-log"
  }
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc/flow-log/${var.project}"
  retention_in_days = 14

  tags = {
    Name = "${var.project}-flow-log-group"
  }
}

data "aws_iam_policy_document" "flow_log_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_log" {
  name               = "${var.project}-vpc-flow-log-role"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume.json

  tags = {
    Name = "${var.project}-vpc-flow-log-role"
  }
}

data "aws_iam_policy_document" "flow_log_permissions" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flow_log" {
  name   = "${var.project}-flow-log-publish"
  role   = aws_iam_role.flow_log.id
  policy = data.aws_iam_policy_document.flow_log_permissions.json
}

############################################
# Lambda security group
############################################
resource "aws_security_group" "lambda" {
  name        = "${var.project}-lambda-sg"
  description = "Security group for Lambda functions in the compute stack"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project}-lambda-sg"
  }
}

# The egress rule — toggled by restrict_egress.
# When restrict_egress = false: allows TCP/443 to DynamoDB VPC endpoint prefix list (working state).
# When restrict_egress = true:  restricts TCP/443 to VPC CIDR only (breaking change — blocks DynamoDB).
resource "aws_security_group_rule" "lambda_egress" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.lambda.id

  prefix_list_ids = var.restrict_egress ? null : [aws_vpc_endpoint.dynamodb.prefix_list_id]
  cidr_blocks     = var.restrict_egress ? [var.vpc_cidr] : null

  description = var.restrict_egress ? "Restricted egress - security audit compliance" : "Allow Lambda to reach DynamoDB via VPC endpoint"
}
