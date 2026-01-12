
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

output "availability_api_url" {
  description = "URL for Availability Checks"
  value       = "http://${aws_instance.app_server.public_ip}:30001"
}

output "order_api_url" {
  description = "URL for Placing Orders"
  value       = "http://${aws_instance.app_server.public_ip}:30002"
}

output "sqs_queue_url" {
  description = "The SQS Queue URL (for debugging)"
  value       = aws_sqs_queue.order_queue.url
}

output "redis_endpoint" {
  description = "Redis ElastiCache endpoint"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "db_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.address
}

output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = aws_opensearch_domain.search.endpoint
}

output "db_password" {
  description = "Database password (for reference)"
  value       = "password123"  # Match the value in databases.tf
  sensitive   = true
}