# 1. Dead Letter Queue (Stores failed messages so they aren't lost)
resource "aws_sqs_queue" "order_dlq" {
  name = "order-fulfillment-dlq"
}

# 2. Main Order Queue
resource "aws_sqs_queue" "order_queue" {
  name                       = "order-fulfillment-queue"
  visibility_timeout_seconds = 30  # Time the worker has to process before retry
  message_retention_seconds  = 86400 # 1 day

  # Link to DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_dlq.arn
    maxReceiveCount     = 3  # Retry 3 times, then move to DLQ
  })
}
