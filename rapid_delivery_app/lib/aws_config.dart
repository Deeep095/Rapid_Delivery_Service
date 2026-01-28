/// =====================================================
/// AWS CONFIGURATION - Rapid Delivery Service
/// =====================================================
///
/// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
/// Generated from: terraform output
/// Run: cd terraform-files && ./generate_flutter_config.ps1
///
/// Generated at: 2026-01-27 22:13:37
/// =====================================================

class AwsConfig {
  // ===================================================================
  // EC2 INSTANCES - Auto-populated from Terraform
  // ===================================================================

  /// API Server IP (K3s Master - runs all services)
  static const String apiServerIp = "100.27.226.157";

  /// Worker Server IP (K3s Agent - extra compute capacity)
  static const String workerServerIp = "13.218.100.236";

  // ===================================================================
  // API ENDPOINTS (via Nginx reverse proxy on port 80)
  // ===================================================================
  
  /// Availability Service URL
  static String get availabilityUrl => "http://$apiServerIp/availability";
  
  /// Order Service URL
  static String get orderUrl => "http://$apiServerIp/order";
  
  /// Health Check URL
  static String get healthUrl => "http://$apiServerIp/health";

  // ===================================================================
  // AWS SERVICES ENDPOINTS (For reference - used by backend, not frontend)
  // ===================================================================

  /// RDS PostgreSQL endpoint
  static const String rdsEndpoint = "rapid-delivery-db.c6t2s662e2x0.us-east-1.rds.amazonaws.com:5432";

  /// ElastiCache Redis endpoint (VPC-only)
  static const String redisEndpoint = "rapid-redis.pqqgpc.0001.use1.cache.amazonaws.com";

  /// OpenSearch URL
  static const String opensearchUrl = "https://search-rapid-search-bu2kcyndpnpudetiv3s6raq5oa.us-east-1.es.amazonaws.com";

  /// SQS Queue URL
  static const String sqsQueueUrl = "https://sqs.us-east-1.amazonaws.com/905418449359/order-fulfillment-queue";

  /// AWS Region
  static const String awsRegion = "us-east-1";

  // ===================================================================
  // VALIDATION
  // ===================================================================
  static bool get isConfigured =>
      apiServerIp.isNotEmpty && apiServerIp != "YOUR_API_SERVER_IP";

  static void printConfig() {
    print("=== AWS Configuration ===");
    print("API Server: $apiServerIp");
    print("Worker Server: $workerServerIp");
    print("Availability URL: $availabilityUrl");
    print("Order URL: $orderUrl");
    print("Configured: $isConfigured");
  }
}
