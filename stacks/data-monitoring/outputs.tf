output "table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.items.name
}

output "table_arn" {
  description = "DynamoDB table ARN"
  value       = aws_dynamodb_table.items.arn
}

output "alarms_sns_topic_arn" {
  description = "SNS topic ARN that alarm notifications fan out from (subscribe the webhook bridge Lambda here)"
  value       = aws_sns_topic.alarms.arn
}

output "lambda_error_alarm_name" {
  description = "Name of the Lambda error-rate alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "dynamodb_capacity_alarm_name" {
  description = "Name of the DynamoDB consumed-capacity alarm (red herring)"
  value       = aws_cloudwatch_metric_alarm.dynamodb_capacity_drop.alarm_name
}
