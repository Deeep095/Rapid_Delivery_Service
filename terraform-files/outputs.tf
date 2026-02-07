
# output "api_gateway_url" {
#   description = "The URL for your Flutter app to call"
#   value       = aws_apigatewayv2_stage.default.invoke_url
# }

# output "k3s_server_public_ip" {
#   description = "The Public IP to SSH into your server"
#   value       = aws_instance.k3s_server.public_ip
# }

# output "rds_endpoint" {
#   value = aws_db_instance.postgres_db.endpoint
# }

# output "elasticache_endpoint" {
#   value = aws_elasticache_cluster.redis_cache.cache_nodes[0].address
# }

# output "opensearch_endpoint" {
#   value = aws_opensearch_domain.search_domain.endpoint
# }

# output "sqs_queue_url" {
#   value = aws_sqs_queue.order_queue.id
# }

# output "server_public_ip" {
#   description = "The Public IP of your EC2 Server. Use this in your Flutter App."
#   value       = aws_instance.app_server.public_ip
# }

# ===================================================================
# EC2 INSTANCES OUTPUTS
# ===================================================================
output "api_server_ip" {
  description = "Public IP of API Server (Availability + Order)"
  value       = aws_instance.api_server.public_ip
}

output "worker_server_ip" {
  description = "Public IP of Worker Server (Fulfillment)"
  value       = aws_instance.worker_server.public_ip
}

output "availability_api_url" {
  description = "URL for Availability Checks (via Nginx on port 80)"
  value       = "http://${aws_instance.api_server.public_ip}/availability"
}

output "order_api_url" {
  description = "URL for Placing Orders (via Nginx on port 80)"
  value       = "http://${aws_instance.api_server.public_ip}/order"
}

output "api_base_url" {
  description = "Base URL for all APIs (via Nginx reverse proxy)"
  value       = "http://${aws_instance.api_server.public_ip}"
}

# ===================================================================
# AWS SERVICES ENDPOINTS (For Local Docker Connection)
# ===================================================================
output "rds_endpoint" {
  description = "PostgreSQL RDS endpoint (publicly accessible)"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_host" {
  description = "PostgreSQL RDS host (without port)"
  value       = aws_db_instance.postgres.address
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint (VPC-only, NOT publicly accessible)"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "opensearch_endpoint" {
  description = "OpenSearch endpoint"
  value       = aws_opensearch_domain.search.endpoint
}

output "opensearch_url" {
  description = "Full OpenSearch URL"
  value       = "https://${aws_opensearch_domain.search.endpoint}"
}

output "sqs_queue_url" {
  description = "SQS Queue URL (publicly accessible via AWS API)"
  value       = aws_sqs_queue.order_queue.url
}

output "sns_topic_arn" {
  description = "SNS Topic ARN for notifications (FREE: 1M requests/month)"
  value       = aws_sns_topic.rapid_notifications.arn
}

output "aws_region" {
  description = "AWS Region"
  value       = var.aws-region
}

# ===================================================================
# CONNECTION SUMMARY
# ===================================================================
output "connection_info" {
  description = "How to connect services"
  value = <<-EOT

  🎯 K3s CLUSTER ARCHITECTURE:
     Master: ${aws_instance.api_server.public_ip} (runs all services)
     Worker: ${aws_instance.worker_server.public_ip} (agent node for extra capacity)
  
  🌐 API ENDPOINTS (via Nginx on port 80):
     Availability: http://${aws_instance.api_server.public_ip}/availability/
     Order:        http://${aws_instance.api_server.public_ip}/order/
     Warehouses:   http://${aws_instance.api_server.public_ip}/warehouses
     Inventory:    http://${aws_instance.api_server.public_ip}/inventory/{warehouse_id}
     Subscribe:    http://${aws_instance.api_server.public_ip}/subscribe
     Health:       http://${aws_instance.api_server.public_ip}/health
  
  📊 AWS SERVICES:
     RDS:        ${aws_db_instance.postgres.endpoint}
     OpenSearch: https://${aws_opensearch_domain.search.endpoint}
     SQS:        ${aws_sqs_queue.order_queue.url}
     SNS:        ${aws_sns_topic.rapid_notifications.arn}
     Redis:      ${aws_elasticache_cluster.redis.cache_nodes[0].address} (VPC-only)
  
  🔑 SSH ACCESS:
     ssh -i k3s-key ubuntu@${aws_instance.api_server.public_ip}
     ssh -i k3s-key ubuntu@${aws_instance.worker_server.public_ip}
  
  📱 FLUTTER CONFIG:
     Run: ./generate_flutter_config.ps1
  EOT
}

output "db_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.address
}

output "db_password" {
  description = "Database password (for reference)"
  value       = "password123"  # Match the value in databases.tf
  sensitive   = true
}