# --- NETWORKING ---
resource "aws_default_vpc" "default" {
  tags = { Name = "Default VPC" }
}

resource "aws_security_group" "rapid_delivery_sg" {
  name        = "rapid-delivery-sg"
  description = "Allow all internal traffic and external web access"
  vpc_id      = aws_default_vpc.default.id

  # Allow HTTP/HTTPS/SSH from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all internal communication (Microservices <-> DBs)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 1. POSTGRES (RDS) ---
resource "aws_db_instance" "postgres" {
  identifier             = "rapid-delivery-db"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = "db.t3.micro" # Free Tier Eligible
  allocated_storage      = 20
  username               = "postgres"
  password               = "password123" # Hardcoded for demo purpose
  skip_final_snapshot    = true
  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.rapid_delivery_sg.id]
}

# --- 2. REDIS (ElastiCache) ---
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "rapid-redis"
  engine               = "redis"
  node_type            = "cache.t2.micro" # Free Tier Eligible
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  security_group_ids   = [aws_security_group.rapid_delivery_sg.id]
}

# --- 3. OPENSEARCH (Free Tier) ---
resource "aws_opensearch_domain" "search" {
  domain_name    = "rapid-search"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type  = "t3.small.search" # Free Tier Eligible 
    instance_count = 1
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
  }

  # Allow access (Simple policy for demo)
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }  //AWS no longer allows wildcard (*) principals for OpenSearch unless you enable fine-grained access control.
      Action    = "es:*"
      Resource  = "arn:aws:es:us-east-1:${data.aws_caller_identity.current.account_id}:domain/rapid-search/*"
    }]
  })
}