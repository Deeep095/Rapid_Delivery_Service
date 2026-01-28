# AWS Deployment Script - Rapid Delivery Service
# This script deploys the complete infrastructure to AWS

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "🚀 Rapid Delivery AWS Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$ErrorActionPreference = "Stop"

# Step 1: Navigate to terraform directory
Write-Host "📁 Step 1: Navigating to Terraform directory..." -ForegroundColor Yellow
Set-Location -Path "terraform-files"

# Step 2: Initialize Terraform
Write-Host "📦 Step 2: Initializing Terraform..." -ForegroundColor Yellow
terraform init

# Step 3: Validate configuration
Write-Host "✅ Step 3: Validating Terraform configuration..." -ForegroundColor Yellow
terraform validate

# Step 4: Plan deployment
Write-Host "📋 Step 4: Planning deployment (review what will be created)..." -ForegroundColor Yellow
terraform plan -out=tfplan

# Step 5: Confirm deployment
Write-Host "Step 5: Ready to deploy to AWS" -ForegroundColor Yellow
$confirm = Read-Host "Do you want to proceed with deployment? (yes/no)"

if ($confirm -ne "yes") {
    Write-Host "❌ Deployment cancelled" -ForegroundColor Red
    exit
}

# Step 6: Apply configuration
Write-Host "Step 6: Deploying to AWS (this will take 8-10 minutes)..." -ForegroundColor Yellow
terraform apply tfplan

# Step 7: Get outputs
Write-Host "Step 7: Deployment complete! Getting service endpoints..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "📍 AWS ENDPOINTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

terraform output

# Step 8: Save outputs to file
terraform output -json | Out-File -FilePath "../aws_endpoints.json"
Write-Host " Endpoints saved to: aws_endpoints.json" -ForegroundColor Green

# Step 8b: Auto-generate Flutter config
Write-Host " Generating Flutter AWS configuration..." -ForegroundColor Yellow
Set-Location ..
.\generate_flutter_config.ps1
Set-Location terraform-files

# Step 9: Display next steps
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "📋 NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Wait 5-7 minutes for EC2 instances to initialize" -ForegroundColor White
Write-Host "2. Update Flutter app with API server IP" -ForegroundColor White
Write-Host "3. Seed the AWS database: python seed_aws.py" -ForegroundColor White
Write-Host "4. Test the APIs" -ForegroundColor White

$api_ip = terraform output -raw api_server_ip 2>$null
if ($api_ip) {
    Write-Host "🔗 API Server: http://$api_ip:30001" -ForegroundColor Cyan
    Write-Host "🔗 Order Service: http://$api_ip:30002" -ForegroundColor Cyan
}

# Write-Host "See AWS_COMPLETE_DEPLOYMENT.md for detailed instructions" -ForegroundColor Yellow
