
provider "aws" {
  region = var.aws-region
}
# --- 2. Get Your Default Network (VPC) ---
# We use the default VPC to avoid NAT Gateway costs
data "aws_vpc" "default" {
  default = true
}
# Get your current Account ID automatically
data "aws_caller_identity" "current" {}

# Get the list of Availability Zones
data "aws_availability_zones" "available" {}

# Ubuntu 22.04 LTS AMI (Official Canonical)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (official Ubuntu owner)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# data "aws_subnets" "default" {
#   filter {
#     name   = "vpc-id"
#     values = [data.aws_vpc.default.id]
#   }
# }

# # --- 3. Create Security Groups (Firewalls) ---

# # This SG is for your K8s (EC2) instance
# resource "aws_security_group" "k3s_sg" {
#   name        = "ec2-k3s-sg"
#   description = "Allow SSH, HTTP, and HTTPS"
#   vpc_id      = data.aws_vpc.default.id

#   # Allow SSH (Port 22) from your IP
#   ingress {
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = [var.my_ip]
#   }

#   # Allow API Gateway to talk to your server
#   # WARNING: This is open to the world. A production setup would lock this
#   # to the specific IP ranges of API Gateway.
#   ingress {
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# # This SG is for your Database
# resource "aws_security_group" "rds_sg" {
#   name        = "rds-sg"
#   description = "Allow K8s (EC2) to connect to RDS"
#   vpc_id      = data.aws_vpc.default.id

#   # Only allow connections from your K8s server
#   ingress {
#     from_port       = 5432 # PostgreSQL port
#     to_port         = 5432
#     protocol        = "tcp"
#     security_groups = [aws_security_group.k3s_sg.id]
#   }
# }

# # This SG is for your Cache
# resource "aws_security_group" "elasticache_sg" {
#   name        = "elasticache-sg"
#   description = "Allow K8s (EC2) to connect to ElastiCache"
#   vpc_id      = data.aws_vpc.default.id

#   # Only allow connections from your K8s server
#   ingress {
#     from_port       = 6379 # Redis port
#     to_port         = 6379
#     protocol        = "tcp"
#     security_groups = [aws_security_group.k3s_sg.id]
#   }
# }

# # This SG is for your Search cluster
# resource "aws_security_group" "opensearch_sg" {
#   name        = "opensearch-sg"
#   description = "Allow K8s (EC2) to connect to OpenSearch"
#   vpc_id      = data.aws_vpc.default.id

#   # Only allow connections from your K8s server
#   ingress {
#     from_port       = 443 # OpenSearch uses HTTPS
#     to_port         = 443
#     protocol        = "tcp"
#     security_groups = [aws_security_group.k3s_sg.id]
#   }
# }

# # --- 4. Create the Data Layer (12-Month Free Tier) ---

# # PostgreSQL Database (RDS)
# resource "aws_db_instance" "postgres_db" {
#   identifier           = "rapid-delivery-db"
#   allocated_storage    = 20 # Free Tier: up to 20 GB
#   instance_class       = "db.t4g.micro" # Free Tier: db.t2.micro or db.t3.micro
#   engine               = "postgres"
#   username             = "dbuser"
#   password             = var.db_password
#   db_subnet_group_name = aws_db_subnet_group.default.name
#   vpc_security_group_ids = [
#   aws_security_group.rds_sg.id]
#   publicly_accessible  = false
#   skip_final_snapshot  = true
# }

# # We need a subnet group for RDS
# resource "aws_db_subnet_group" "default" {
#   name       = "main-db-subnet-group"
#   subnet_ids = data.aws_subnets.default.ids
# }

# # Redis Cache (ElastiCache)
# # This is the correct, standalone, free-tier setup
# resource "aws_elasticache_cluster" "redis_cache" {
#   cluster_id           = "rapid-delivery-cache"
#   engine               = "redis"
#   node_type            = "cache.t4g.micro" # Free Tier: cache.t4g.micro
#   num_cache_nodes      = 1
#   port                 = 6379
#   subnet_group_name    = aws_elasticache_subnet_group.default.name
#   security_group_ids   = [aws_security_group.elasticache_sg.id]
#   engine_version       = "7.0"
#   parameter_group_name = "default.redis7"
# }

# # We also need a subnet group for ElastiCache
# resource "aws_elasticache_subnet_group" "default" {
#   name       = "main-cache-subnet-group"
#   subnet_ids = data.aws_subnets.default.ids
# }

# # OpenSearch Cluster
# resource "aws_opensearch_domain" "search_domain" {
#   domain_name    = "rapid-delivery-search"
#   engine_version = "OpenSearch_2.11"

#   cluster_config {
#     instance_type = "t3.small.search" # Free Tier: t3.small.search
#   }

#   ebs_options {
#     ebs_enabled = true
#     volume_size = 10 # Free Tier: up to 10 GB
#   }

#   # This puts the cluster inside your VPC so it's not public
#   vpc_options {
#     subnet_ids         = slice(data.aws_subnets.default.ids, 0, 1) # Needs at least 1 subnet
#     security_group_ids = [aws_security_group.opensearch_sg.id]
#   }

#   # Allows our EC2 instance (via its IAM role) to access the cluster
#   access_policies = jsonencode({
#     "Version" : "2012-10-17",
#     "Statement" : [
#       {
#         "Effect" : "Allow",
#         "Principal" : {
#           "AWS" : [aws_iam_role.k3s_role.arn]
#         },
#         "Action" : "es:*",
#         "Resource" : "arn:aws:es:${var.aws-region}:${data.aws_caller_identity.current.account_id}:domain/rapid-delivery-search/*"
#       }
#     ]
#   })
# }

# data "aws_caller_identity" "current" {}


# # --- 5. Create Eventing Layer (Permanent Free Tier) ---

# resource "aws_sqs_queue" "order_queue" {
#   name = "order-queue"
# }

# resource "aws_sns_topic" "inventory_alerts" {
#   name = "inventory-alerts"
# }

# # --- 6. Create Compute Layer (12-Month Free Tier) ---

# # IAM Role for the EC2 instance
# resource "aws_iam_role" "k3s_role" {
#   name = "k3s-pod-role"
#   assume_role_policy = jsonencode({
#     "Version" : "2012-10-17",
#     "Statement" : [
#       {
#         "Effect" : "Allow",
#         "Principal" : {
#           "Service" : "ec2.amazonaws.com"
#         },
#         "Action" : "sts:AssumeRole"
#       }
#     ]
#   })
# }

# # Attach policies to the role
# resource "aws_iam_role_policy_attachment" "sqs" {
#   role       = aws_iam_role.k3s_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
# }
# resource "aws_iam_role_policy_attachment" "sns" {
#   role       = aws_iam_role.k3s_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
# }

# resource "aws_iam_instance_profile" "k3s_profile" {
#   name = "k3s-instance-profile"
#   role = aws_iam_role.k3s_role.name
# }

# # This is the SSH key you will use to log in
# resource "aws_key_pair" "k3s_key" {
#   key_name   = "k3s-key"
#   public_key = file(var.public_key_path)
# }

# # The EC2 Instance
# resource "aws_instance" "k3s_server" {
#   ami           = "ami-0cae6d6fe6048ca2c" # Amazon Linux 2023 (us-east-1)
#   instance_type = "t2.micro"              # Free Tier: t2.micro
#   key_name      = aws_key_pair.k3s_key.key_name
#   vpc_security_group_ids = [
#   aws_security_group.k3s_sg.id]
#   iam_instance_profile = aws_iam_instance_profile.k3s_profile.name

#   tags = {
#     Name = "k3s-server"
#   }
# }

# # --- 7. Create API Gateway (Permanent Free Tier) ---
# resource "aws_apigatewayv2_api" "http_api" {
#   name          = "RapidDeliveryAPI-Terraform"
#   protocol_type = "HTTP"
# }

# # This integration points to our EC2 instance's public IP
# resource "aws_apigatewayv2_integration" "http_proxy" {
#   api_id             = aws_apigatewayv2_api.http_api.id
#   integration_type   = "HTTP_PROXY"
#   integration_method = "ANY"
#   # This dynamically uses the public IP of the k3s_server
#   integration_uri = "http://${aws_instance.k3s_server.public_dns}"
# }

# # This route forwards ALL requests (e.g., /availability, /order)
# resource "aws_apigatewayv2_route" "http_proxy" {
#   api_id    = aws_apigatewayv2_api.http_api.id
#   route_key = "ANY /{proxy+}"
#   target    = "integrations/${aws_apigatewayv2_integration.http_proxy.id}"
# }

# # A default stage to make the API live
# resource "aws_apigatewayv2_stage" "default" {
#   api_id      = aws_apigatewayv2_api.http_api.id
#   name        = "$default"
#   auto_deploy = true
# }

