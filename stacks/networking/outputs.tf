output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs (Lambda will run in these)"
  value       = aws_subnet.private[*].id
}

output "lambda_security_group_id" {
  description = "Security group ID assigned to Lambda functions"
  value       = aws_security_group.lambda.id
}

output "dynamodb_vpc_endpoint_id" {
  description = "DynamoDB Gateway VPC endpoint ID"
  value       = aws_vpc_endpoint.dynamodb.id
}

output "dynamodb_prefix_list_id" {
  description = "DynamoDB VPC endpoint prefix list ID"
  value       = aws_vpc_endpoint.dynamodb.prefix_list_id
}

output "region" {
  description = "AWS region"
  value       = var.region
}
