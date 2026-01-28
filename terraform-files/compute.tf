

resource "aws_iam_role" "ec2_role" {
  name = "rapid_delivery_ec2_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

# 1. Allow ECR Pull and Push
resource "aws_iam_role_policy_attachment" "ecr_power_user" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# 2. Allow SQS Access (Critical for the new architecture)
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
        Resource = aws_sqs_queue.order_queue.arn #"*"
      }
    ]
  })
}

# 3. Allow SSM Parameter Store Access (for K3s token sharing between nodes)
resource "aws_iam_role_policy" "ssm_policy" {
  name = "ssm_access_policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws-region}:${data.aws_caller_identity.current.account_id}:parameter/rapid-delivery/*"
      }
    ]
  })
}

# 4. Allow OpenSearch Access (for warehouse geo-queries)
resource "aws_iam_role_policy" "opensearch_policy" {
  name = "opensearch_access_policy"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "es:ESHttpGet",
          "es:ESHttpPut",
          "es:ESHttpPost",
          "es:ESHttpDelete"
        ]
        Resource = "arn:aws:es:${var.aws-region}:${data.aws_caller_identity.current.account_id}:domain/rapid-search/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "rapid_delivery_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_key_pair" "k3s_key" {
  key_name   = "k3s-key"
  public_key = file("${path.module}/k3s-key.pub")
}

# ===================================================================
# INSTANCE 1: K3s MASTER (API Server + All Deployments)
# Runs K3s server, deploys all services, exposes via Nginx on port 80
# ===================================================================
resource "aws_instance" "api_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro" # Free Tier - 1GB RAM
  
  key_name = aws_key_pair.k3s_key.key_name
  vpc_security_group_ids = [aws_security_group.rapid_delivery_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = 20 # Free tier
    volume_type = "gp2"
    delete_on_termination = true
  }

  # K3s Master - deploys all services, saves token to SSM
  user_data = templatefile("user_data_api.sh", {
    AVAIL_IMAGE_URL       = aws_ecr_repository.availability_repo.repository_url
    ORDER_IMAGE_URL       = aws_ecr_repository.order_repo.repository_url
    FULFILLMENT_IMAGE_URL = aws_ecr_repository.fulfillment_repo.repository_url
    SQS_QUEUE_URL         = aws_sqs_queue.order_queue.url
    SNS_TOPIC_ARN         = aws_sns_topic.rapid_notifications.arn
    OPENSEARCH_ENDPOINT   = aws_opensearch_domain.search.endpoint
    REDIS_ENDPOINT        = aws_elasticache_cluster.redis.cache_nodes[0].address
    DB_ENDPOINT           = aws_db_instance.postgres.address
    ACCOUNT_ID            = data.aws_caller_identity.current.account_id
    AWS_REGION            = var.aws-region 
  })

  depends_on = [
    aws_db_instance.postgres,
    aws_elasticache_cluster.redis,
    aws_opensearch_domain.search
  ]

  tags = { 
    Name = "RapidDelivery-K3s-Master" 
    Role = "master"
  }
}

# ===================================================================
# INSTANCE 2: K3s WORKER (Agent Node)
# Joins the master cluster, provides extra compute capacity
# ===================================================================
resource "aws_instance" "worker_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro" # Free Tier - 1GB RAM
  
  key_name = aws_key_pair.k3s_key.key_name
  vpc_security_group_ids = [aws_security_group.rapid_delivery_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = 20 # Free tier
    volume_type = "gp2"
    delete_on_termination = true
  }

  # K3s Agent - joins master cluster via SSM token
  user_data = templatefile("user_data_worker.sh", {
    ACCOUNT_ID = data.aws_caller_identity.current.account_id
    AWS_REGION = var.aws-region 
  })

  # Worker must wait for master to be ready
  depends_on = [
    aws_instance.api_server,
    aws_db_instance.postgres,
    aws_elasticache_cluster.redis
  ]

  tags = { 
    Name = "RapidDelivery-K3s-Worker"
    Role = "worker"
  }
}



