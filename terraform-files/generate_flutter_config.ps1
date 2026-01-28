#!/usr/bin/env pwsh
# ============================================================
# Generate Flutter aws_config.dart from Terraform outputs
# ============================================================
# Run this after `terraform apply` to update Flutter config
# Usage: ./generate_flutter_config.ps1
# ============================================================

$ErrorActionPreference = "Stop"

Write-Host "🔧 Generating Flutter AWS Config from Terraform outputs..." -ForegroundColor Cyan

# Check if we're in the terraform directory
if (-not (Test-Path "terraform.tfstate")) {
    Write-Host "❌ Error: terraform.tfstate not found. Run this from terraform-files directory." -ForegroundColor Red
    exit 1
}

# Get terraform outputs as JSON
Write-Host "📊 Reading Terraform outputs..." -ForegroundColor Yellow
$outputs = terraform output -json | ConvertFrom-Json

# Extract values
$apiServerIp = $outputs.api_server_ip.value
$workerServerIp = $outputs.worker_server_ip.value
$rdsEndpoint = $outputs.rds_endpoint.value
$redisEndpoint = $outputs.redis_endpoint.value
$opensearchUrl = $outputs.opensearch_url.value
$sqsQueueUrl = $outputs.sqs_queue_url.value
$awsRegion = $outputs.aws_region.value

Write-Host "✅ API Server IP: $apiServerIp" -ForegroundColor Green
Write-Host "✅ Worker Server IP: $workerServerIp" -ForegroundColor Green

# Generate the Dart file
$dartContent = @"
/// AWS CONFIGURATION - Rapid Delivery Service
///
/// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
/// Generated from: terraform output
/// Run: cd terraform-files && ./generate_flutter_config.ps1
///
/// Generated at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

class AwsConfig {
  // EC2 INSTANCES - Auto-populated from Terraform

  /// API Server IP (K3s Master - runs all services)
  static const String apiServerIp = "$apiServerIp";

  /// Worker Server IP (K3s Agent - extra compute capacity)
  static const String workerServerIp = "$workerServerIp";



  // API ENDPOINTS (via Nginx reverse proxy on port 80)
  
  /// Availability Service URL
  static String get availabilityUrl => "http://`$apiServerIp/availability";
  
  /// Order Service URL
  static String get orderUrl => "http://`$apiServerIp/order";
  
  /// Health Check URL
  static String get healthUrl => "http://`$apiServerIp/health";



  // AWS SERVICES ENDPOINTS (For reference - used by backend, not frontend)

  /// RDS PostgreSQL endpoint
  static const String rdsEndpoint = "$rdsEndpoint";

  /// ElastiCache Redis endpoint (VPC-only)
  static const String redisEndpoint = "$redisEndpoint";

  /// OpenSearch URL
  static const String opensearchUrl = "$opensearchUrl";

  /// SQS Queue URL
  static const String sqsQueueUrl = "$sqsQueueUrl";

  /// AWS Region
  static const String awsRegion = "$awsRegion";

  

  // VALIDATION
  static bool get isConfigured =>
      apiServerIp.isNotEmpty && apiServerIp != "YOUR_API_SERVER_IP";

  static void printConfig() {
    print("=== AWS Configuration ===");
    print("API Server: `$apiServerIp");
    print("Worker Server: `$workerServerIp");
    print("Availability URL: `$availabilityUrl");
    print("Order URL: `$orderUrl");
    print("Configured: `$isConfigured");
  }
}
"@

# Write to Flutter app
$flutterConfigPath = "..\rapid_delivery_app\lib\aws_config.dart"

if (-not (Test-Path "..\rapid_delivery_app\lib")) {
    Write-Host "⚠️  Flutter app directory not found at expected location." -ForegroundColor Yellow
    Write-Host "   Saving to current directory instead." -ForegroundColor Yellow
    $flutterConfigPath = "aws_config.dart"
}

$dartContent | Out-File -FilePath $flutterConfigPath -Encoding utf8

Write-Host ""
Write-Host "✅ Flutter config generated: $flutterConfigPath" -ForegroundColor Green
Write-Host ""
Write-Host "📱 API Endpoints:" -ForegroundColor Cyan
Write-Host "   Availability: http://$apiServerIp/availability/" -ForegroundColor White
Write-Host "   Order:        http://$apiServerIp/order/" -ForegroundColor White
Write-Host "   Health:       http://$apiServerIp/health" -ForegroundColor White
Write-Host ""
Write-Host "🔑 SSH Access:" -ForegroundColor Cyan
Write-Host "   Master: ssh -i k3s-key ubuntu@$apiServerIp" -ForegroundColor White
Write-Host "   Worker: ssh -i k3s-key ubuntu@$workerServerIp" -ForegroundColor White
Write-Host ""
Write-Host "🎉 Done! You can now run the Flutter app." -ForegroundColor Green
