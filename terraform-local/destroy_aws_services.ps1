<#
.SYNOPSIS
    Destroys expensive AWS managed services (OpenSearch, RDS, ElastiCache) to save costs.
    
.DESCRIPTION
    This script destroys only the expensive AWS managed services from terraform-files:
    - OpenSearch domain (~$30/month)
    - RDS PostgreSQL instance (~$18/month)
    - ElastiCache Redis cluster (~$13/month)
    
    Total savings: ~$55-65/month
    
    EC2 instances, SQS, SNS, and ECR are NOT destroyed (free tier eligible).
    
.NOTES
    Run this BEFORE deploying terraform-local to avoid duplicate resources.
#>

Write-Host "============================================" -ForegroundColor Yellow
Write-Host "DESTROY EXPENSIVE AWS SERVICES" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "This will destroy the following resources:" -ForegroundColor Red
Write-Host "  - aws_opensearch_domain.search (~`$30/month)" -ForegroundColor Red
Write-Host "  - aws_db_instance.postgres (~`$18/month)" -ForegroundColor Red
Write-Host "  - aws_elasticache_cluster.redis (~`$13/month)" -ForegroundColor Red
Write-Host ""
Write-Host "This will KEEP (free tier):" -ForegroundColor Green
Write-Host "  - EC2 instances" -ForegroundColor Green
Write-Host "  - SQS queues" -ForegroundColor Green
Write-Host "  - SNS topics" -ForegroundColor Green
Write-Host "  - ECR repositories" -ForegroundColor Green
Write-Host ""
Write-Host "Total monthly savings: ~`$55-65" -ForegroundColor Cyan
Write-Host ""

$confirm = Read-Host "Are you sure you want to destroy these resources? (yes/no)"

if ($confirm -ne "yes") {
    Write-Host "Aborted." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Changing to terraform-files directory..." -ForegroundColor Cyan
Set-Location -Path "$PSScriptRoot\..\terraform-files"

Write-Host ""
Write-Host "Step 1: Destroying OpenSearch domain..." -ForegroundColor Cyan
terraform destroy -target=aws_opensearch_domain.search -auto-approve

Write-Host ""
Write-Host "Step 2: Destroying RDS PostgreSQL..." -ForegroundColor Cyan
terraform destroy -target=aws_db_instance.postgres -auto-approve

Write-Host ""
Write-Host "Step 3: Destroying ElastiCache Redis..." -ForegroundColor Cyan
terraform destroy -target=aws_elasticache_cluster.redis -auto-approve

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "DONE! Expensive services destroyed." -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. cd terraform-local" -ForegroundColor White
Write-Host "  2. terraform init" -ForegroundColor White
Write-Host "  3. terraform apply" -ForegroundColor White
Write-Host ""
Write-Host "The new setup runs PostgreSQL, Redis, and OpenSearch" -ForegroundColor Cyan
Write-Host "on EC2 via Docker, saving you ~`$55-65/month!" -ForegroundColor Cyan
