# =============================================================================
# SQS and SNS - Remain on AWS (FREE TIER: 1M requests/month)
# =============================================================================

# Dead Letter Queue
resource "aws_sqs_queue" "order_dlq" {
  name = "order-fulfillment-dlq-local"
}

# Main Order Queue
resource "aws_sqs_queue" "order_queue" {
  name                       = "order-fulfillment-queue-local"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400 # 1 day

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_dlq.arn
    maxReceiveCount     = 3
  })
}

# SNS Topic for notifications
resource "aws_sns_topic" "rapid_notifications" {
  name = "rapid-delivery-notifications-local"
  
  tags = {
    Name        = "RapidDeliveryNotifications"
    Environment = "local"
  }
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "rapid_notifications_policy" {
  arn = aws_sns_topic.rapid_notifications.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEC2Publish"
        Effect    = "Allow"
        Principal = "*"
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.rapid_notifications.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}
