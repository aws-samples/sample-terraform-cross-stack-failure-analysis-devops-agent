############################################
# DynamoDB table
############################################
resource "aws_dynamodb_table" "items" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = var.table_name
  }
}

############################################
# SNS topic for alarms — webhook bridge Lambda subscribes to this
############################################
resource "aws_sns_topic" "alarms" {
  name              = "${var.project}-alarms"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name = "${var.project}-alarms"
  }
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

############################################
# Alarm 1: Lambda error rate spike (real signal)
############################################
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project}-lambda-error-rate"
  alarm_description   = "Fires when the API Lambda is throwing errors (likely cause of upstream impact)."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name = "${var.project}-lambda-error-rate"
  }
}

############################################
# Alarm 2: DynamoDB consumed read capacity drops to ~zero (THE RED HERRING)
# This looks like a DynamoDB problem but is actually because requests never arrive.
############################################
resource "aws_cloudwatch_metric_alarm" "dynamodb_capacity_drop" {
  alarm_name          = "${var.project}-dynamodb-read-capacity-drop"
  alarm_description   = "Fires when DynamoDB consumed read capacity drops to near zero — looks like DDB issue but often means requests aren't arriving."
  namespace           = "AWS/DynamoDB"
  metric_name         = "ConsumedReadCapacityUnits"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    TableName = aws_dynamodb_table.items.name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  tags = {
    Name = "${var.project}-dynamodb-read-capacity-drop"
  }
}
