# =============================================================================
# IAM Roles and Policies for EC2
# =============================================================================

resource "aws_iam_role" "ec2_role" {
  name = "rapid_delivery_ec2_role_local"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# ECR Pull/Push
resource "aws_iam_role_policy_attachment" "ecr_power_user" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# SQS Access
resource "aws_iam_role_policy" "sqs_policy" {
  name = "sqs_access_policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      Resource = aws_sqs_queue.order_queue.arn
    }]
  })
}

# SSM Parameter Store (for K3s token sharing)
resource "aws_iam_role_policy" "ssm_policy" {
  name = "ssm_access_policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:DeleteParameter"
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/rapid-delivery-local/*"
    }]
  })
}

# SNS Publish
resource "aws_iam_role_policy" "sns_policy" {
  name = "sns_publish_policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = aws_sns_topic.rapid_notifications.arn
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "rapid_delivery_profile_local"
  role = aws_iam_role.ec2_role.name
}

# SSH Key
resource "aws_key_pair" "k3s_key" {
  key_name   = "k3s-key-local"
  public_key = file("${path.module}/k3s-key.pub")
}
