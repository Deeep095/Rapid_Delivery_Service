resource "aws_iam_role" "ec2_role" {
  name = "rapid_delivery_ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

# 1. Allow ECR Pull (Existing)
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# 2. NEW: Allow SQS Access (Critical for the new architecture)
resource "aws_iam_role_policy" "sqs_policy" {
  name = "sqs_access_policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "rapid_delivery_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "app_server" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS (US-East-1)
  instance_type = "t3.micro" # Free Tier
  
  key_name = "vockey" # Use 'vockey' if using Learner Lab, or create a keypair if personal account

  vpc_security_group_ids = [aws_security_group.rapid_delivery_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

    # Inject Database Endpoints into the startup script
    user_data = templatefile("user_data.sh", {
    AVAIL_IMAGE_URL     = aws_ecr_repository.availability_repo.repository_url
    ORDER_IMAGE_URL     = aws_ecr_repository.order_repo.repository_url

    WORKER_IMAGE_URL    = aws_ecr_repository.inventory_repo.repository_url
    SQS_QUEUE_URL       = aws_sqs_queue.order_queue.id
    OPENSEARCH_ENDPOINT = aws_opensearch_domain.search.endpoint
    REDIS_ENDPOINT      = aws_elasticache_cluster.redis.cache_nodes[0].address
    DB_ENDPOINT         = aws_db_instance.postgres.address
    ACCOUNT_ID          = data.aws_caller_identity.current.account_id
  })

  depends_on = [
    null_resource.docker_build_push,
    aws_db_instance.postgres,
    aws_elasticache_cluster.redis
  ]

  tags = { Name = "RapidDelivery-K3s-Node" }
}



