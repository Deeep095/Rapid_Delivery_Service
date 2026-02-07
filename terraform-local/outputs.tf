# =============================================================================
# OUTPUTS - Local Setup
# =============================================================================

# ===================================================================
# EC2 INSTANCES
# ===================================================================
output "api_server_ip" {
  description = "Public IP of API Server (runs K3s + Docker DBs)"
  value       = aws_instance.api_server.public_ip
}

output "worker_server_ip" {
  description = "Public IP of Worker Server"
  value       = aws_instance.worker_server.public_ip
}

output "api_base_url" {
  description = "Base URL for all APIs (via Nginx reverse proxy)"
  value       = "http://${aws_instance.api_server.public_ip}"
}

# ===================================================================
# LOCAL DATABASES (Docker on EC2)
# ===================================================================
output "local_postgres" {
  description = "PostgreSQL (Docker) - replaces RDS"
  value       = "postgresql://postgres:${var.db_password}@${aws_instance.api_server.public_ip}:5432/postgres"
  sensitive   = true
}

output "local_redis" {
  description = "Redis (Docker) - replaces ElastiCache"
  value       = "${aws_instance.api_server.public_ip}:6379"
}

output "local_opensearch" {
  description = "OpenSearch (Docker) - replaces AWS OpenSearch"
  value       = "http://${aws_instance.api_server.public_ip}:9200"
}

# ===================================================================
# AWS SERVICES (Free Tier)
# ===================================================================
output "sqs_queue_url" {
  description = "SQS Queue URL"
  value       = aws_sqs_queue.order_queue.url
}

output "sns_topic_arn" {
  description = "SNS Topic ARN"
  value       = aws_sns_topic.rapid_notifications.arn
}

output "aws_region" {
  description = "AWS Region"
  value       = var.aws_region
}

# ===================================================================
# ECR REPOSITORIES
# ===================================================================
output "ecr_availability" {
  description = "ECR repo for availability service"
  value       = aws_ecr_repository.availability_repo.repository_url
}

output "ecr_order" {
  description = "ECR repo for order service"
  value       = aws_ecr_repository.order_repo.repository_url
}

output "ecr_fulfillment" {
  description = "ECR repo for fulfillment worker"
  value       = aws_ecr_repository.fulfillment_repo.repository_url
}

# ===================================================================
# CONNECTION SUMMARY
# ===================================================================
output "connection_info" {
  description = "How to connect to services"
  value = <<-EOT

    COST SAVINGS: ~$55-65/month compared to AWS managed services!
  
    K3s CLUSTER:
     Master: ${aws_instance.api_server.public_ip} (runs K3s + Docker DBs)
     Worker: ${aws_instance.worker_server.public_ip} (agent node)
  
    API ENDPOINTS (via Nginx on port 80):
     Base URL:     http://${aws_instance.api_server.public_ip}
     Availability: http://${aws_instance.api_server.public_ip}/availability/
     Order:        http://${aws_instance.api_server.public_ip}/order/
     Warehouses:   http://${aws_instance.api_server.public_ip}/warehouses
     Health:       http://${aws_instance.api_server.public_ip}/health
  
    LOCAL DATABASES (Docker on EC2):
     PostgreSQL:  ${aws_instance.api_server.private_ip}:5432 (inside EC2)
     Redis:       ${aws_instance.api_server.private_ip}:6379 (inside EC2)
     OpenSearch:  http://${aws_instance.api_server.private_ip}:9200 (inside EC2)
  
    AWS SERVICES (Free Tier):
     SQS: ${aws_sqs_queue.order_queue.url}
     SNS: ${aws_sns_topic.rapid_notifications.arn}
  
    SSH ACCESS:
     ssh -i k3s-key ubuntu@${aws_instance.api_server.public_ip}
     ssh -i k3s-key ubuntu@${aws_instance.worker_server.public_ip}
  
    CHECK DOCKER CONTAINERS (after SSH):
     docker ps
     docker logs postgres
     docker logs redis
     docker logs opensearch
  
    UPDATE FLUTTER CONFIG:
     Update lib/aws_config.dart with: http://${aws_instance.api_server.public_ip}
  EOT
}

output "cost_savings" {
  description = "Monthly cost savings"
  value = <<-EOT
  
    MONTHLY COST COMPARISON:
  
  AWS Managed Services (OLD):
    - OpenSearch t3.small.search: ~$30/month
    - RDS db.t3.micro:            ~$18/month
    - ElastiCache cache.t2.micro: ~$13/month
    - TOTAL:                      ~$61/month
  
  Local Docker on EC2 (NEW):
    - t3.small EC2:               ~$15/month
    - TOTAL:                      ~$15/month
  
    SAVINGS:                     ~$46/month (~$550/year!)
  EOT
}
