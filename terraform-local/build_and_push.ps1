<#
.SYNOPSIS
    Builds and pushes Docker images to ECR for the local setup.
    
.DESCRIPTION
    This script builds the three microservices and pushes them to the 
    local setup ECR repositories.
#>

param(
    [string]$Region = "us-east-1"
)

Write-Host "BUILD AND PUSH TO ECR (Local Setup)" -ForegroundColor Cyan

# Get AWS Account ID
$AccountId = aws sts get-caller-identity --query Account --output text
Write-Host "AWS Account ID: $AccountId" -ForegroundColor Green

# Login to ECR
Write-Host "Logging in to ECR..." -ForegroundColor Cyan
aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin "$AccountId.dkr.ecr.$Region.amazonaws.com"

# Build and push availability-service
Write-Host ""
Write-Host "Building availability-service..." -ForegroundColor Yellow
Set-Location "$PSScriptRoot\..\availability-service"
docker build -t "$AccountId.dkr.ecr.$Region.amazonaws.com/availability-service-local:latest" .
docker push "$AccountId.dkr.ecr.$Region.amazonaws.com/availability-service-local:latest"

# Build and push order-service
Write-Host ""
Write-Host "Building order-service..." -ForegroundColor Yellow
Set-Location "$PSScriptRoot\..\order-service"
docker build -t "$AccountId.dkr.ecr.$Region.amazonaws.com/order-service-local:latest" .
docker push "$AccountId.dkr.ecr.$Region.amazonaws.com/order-service-local:latest"

# Build and push fulfillment-worker
Write-Host ""
Write-Host "Building fulfillment-worker..." -ForegroundColor Yellow
Set-Location "$PSScriptRoot\..\fulfillment-worker"
docker build -t "$AccountId.dkr.ecr.$Region.amazonaws.com/fulfillment-worker-local:latest" .
docker push "$AccountId.dkr.ecr.$Region.amazonaws.com/fulfillment-worker-local:latest"

Write-Host ""
Write-Host "All images pushed to ECR!" -ForegroundColor Green

Set-Location "$PSScriptRoot"
