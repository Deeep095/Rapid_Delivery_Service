

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

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "rapid_delivery_profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "app_server" {
  ami           =  data.aws_ami.ubuntu.id #"ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS (US-East-1)
  instance_type = "t3.micro" # Free Tier
  
  key_name = "vockey" # Use 'vockey' if using Learner Lab, or create a keypair if personal account

  vpc_security_group_ids = [aws_security_group.rapid_delivery_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = 20          # Free tier (<=30 GB)
    volume_type = "gp2"
    delete_on_termination = true
  }


  # Inject Database Endpoints into the startup script
  user_data = templatefile("user_data.sh", 
  {
    AVAIL_IMAGE_URL     = aws_ecr_repository.availability_repo.repository_url
    ORDER_IMAGE_URL     = aws_ecr_repository.order_repo.repository_url

    FULFILLMENT_IMAGE_URL  = aws_ecr_repository.fulfillment_repo.repository_url
    SQS_QUEUE_URL       = aws_sqs_queue.order_queue.url
    OPENSEARCH_ENDPOINT = aws_opensearch_domain.search.endpoint
    REDIS_ENDPOINT      = aws_elasticache_cluster.redis.cache_nodes[0].address
    DB_ENDPOINT         = aws_db_instance.postgres.address
    ACCOUNT_ID          = data.aws_caller_identity.current.account_id
    AWS_REGION          = var.aws-region 
  })

  depends_on = [
    aws_db_instance.postgres,
    aws_elasticache_cluster.redis,
    aws_opensearch_domain.search
  ]

  tags = { Name = "RapidDelivery-K3s-Node" }
}



