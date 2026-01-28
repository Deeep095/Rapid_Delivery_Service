# 1. Dead Letter Queue (Stores failed messages so they aren't lost)
resource "aws_sqs_queue" "order_dlq" {
  name = "order-fulfillment-dlq"
}

# 2. Main Order Queue
resource "aws_sqs_queue" "order_queue" {
  name                       = "order-fulfillment-queue"
  visibility_timeout_seconds = 30    # Time the worker has to process before retry
  message_retention_seconds  = 86400 # 1 day

  # Link to DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_dlq.arn
    maxReceiveCount     = 3 # Retry 3 times, then move to DLQ
  })
}

# =====================================================
# SNS TOPIC FOR NOTIFICATIONS (FREE TIER: 1M requests/month)
# =====================================================

# SNS Topic for order and inventory notifications
resource "aws_sns_topic" "rapid_notifications" {
  name = "rapid-delivery-notifications"
  
  tags = {
    Name = "RapidDeliveryNotifications"
    Environment = "demo"
  }
}

# SNS Topic Policy - Allow services to publish
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
            "aws:SourceArn" = "arn:aws:ec2:${var.aws-region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}
