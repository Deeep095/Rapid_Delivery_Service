# =====================================================
# CHECK AWS DEPLOYMENT STATUS
# =====================================================

Write-Host "`n🔍 Checking AWS Deployment Status...`n" -ForegroundColor Cyan

cd terraform-files

# Get IPs
$apiIp = terraform output -raw api_server_ip 2>$null
$workerIp = terraform output -raw worker_server_ip 2>$null

if (-not $apiIp) {
    Write-Host "❌ No Terraform outputs found. Run terraform apply first." -ForegroundColor Red
    exit 1
}

Write-Host "📍 EC2 Instances:" -ForegroundColor Yellow
Write-Host "   API Server: $apiIp" -ForegroundColor White
Write-Host "   Worker Server: $workerIp" -ForegroundColor White

# Check API Server
Write-Host "`n🔍 Checking API Server ($apiIp)..." -ForegroundColor Yellow
Write-Host "   Testing HTTP endpoints..." -ForegroundColor Gray

try {
    $avail = Invoke-WebRequest -Uri "http://$apiIp:30001/" -TimeoutSec 5 -ErrorAction Stop
    Write-Host "   ✅ Availability Service: RUNNING" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Availability Service: NOT RESPONDING" -ForegroundColor Red
}

try {
    $order = Invoke-WebRequest -Uri "http://$apiIp:30002/" -TimeoutSec 5 -ErrorAction Stop
    Write-Host "   ✅ Order Service: RUNNING" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Order Service: NOT RESPONDING" -ForegroundColor Red
}

# Check pods via SSH
Write-Host "`n   Checking Kubernetes pods..." -ForegroundColor Gray
$keyPath = "k3s-key"
if (Test-Path $keyPath) {
    $pods = ssh -o ConnectTimeout=10 -i $keyPath ubuntu@$apiIp "kubectl get pods -A 2>&1"
    if ($LASTEXITCODE -eq 0) {
        Write-Host $pods
    } else {
        Write-Host "   ⚠️  Could not connect via SSH (pods may still be initializing)" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ⚠️  SSH key not found at: $keyPath" -ForegroundColor Yellow
}

# Check Worker Server
Write-Host "`n🔍 Checking Worker Server ($workerIp)..." -ForegroundColor Yellow
if (Test-Path $keyPath) {
    $workerPods = ssh -o ConnectTimeout=10 -i $keyPath ubuntu@$workerIp "kubectl get pods -A 2>&1"
    if ($LASTEXITCODE -eq 0) {
        Write-Host $workerPods
    } else {
        Write-Host "   ⚠️  Could not connect via SSH (pods may still be initializing)" -ForegroundColor Yellow
    }
}

Write-Host "`n📋 Troubleshooting:" -ForegroundColor Yellow
Write-Host "   If pods aren't running, SSH in and check:" -ForegroundColor White
Write-Host "   ssh -i $keyPath ubuntu@$apiIp" -ForegroundColor Gray
Write-Host "   sudo tail -100 /var/log/cloud-init-output.log" -ForegroundColor Gray
Write-Host "   kubectl get pods -A" -ForegroundColor Gray
Write-Host "   kubectl logs -l app=availability" -ForegroundColor Gray

cd ..
