# PowerShell script to quickly test the deployed services
# Usage: .\test-services.ps1

Write-Host "=== Rapid Delivery Service Quick Test ===" -ForegroundColor Cyan

# Get EC2 IP from Terraform output
$ErrorActionPreference = "Continue"
Push-Location "terraform-files"

try {
    $availabilityUrl = terraform output -raw availability_api_url 2>&1
    $orderUrl = terraform output -raw order_api_url 2>&1
    
    if ($availabilityUrl -match "Error") {
        Write-Host "Error getting Terraform outputs. Make sure you're in the right directory." -ForegroundColor Red
        Write-Host "Trying default IP: 54.205.187.126" -ForegroundColor Yellow
        $availabilityUrl = "http://54.205.187.126:30001"
        $orderUrl = "http://54.205.187.126:30002"
    }
    
    Write-Host "`n1. Testing Availability Service..." -ForegroundColor Yellow
    Write-Host "   URL: $availabilityUrl"
    try {
        $response = Invoke-WebRequest -Uri $availabilityUrl -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            Write-Host "   ✅ Status: $($response.StatusCode)" -ForegroundColor Green
            Write-Host "   Response: $($response.Content)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "   ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "`n2. Testing Order Service..." -ForegroundColor Yellow
    Write-Host "   URL: $orderUrl"
    try {
        $response = Invoke-WebRequest -Uri $orderUrl -UseBasicParsing -TimeoutSec 5
        if ($response.StatusCode -eq 200) {
            Write-Host "   ✅ Status: $($response.StatusCode)" -ForegroundColor Green
            Write-Host "   Response: $($response.Content)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "   ❌ Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "1. SSH into EC2: ssh -i terraform-files/k3s-key ubuntu@54.205.187.126" -ForegroundColor White
    Write-Host "2. Check pods: k3s kubectl get pods" -ForegroundColor White
    Write-Host "3. Check logs: k3s kubectl logs deployment/availability-app" -ForegroundColor White
    Write-Host "4. Check ConfigMap: k3s kubectl get configmap app-config -o yaml" -ForegroundColor White
    
} finally {
    Pop-Location
}
