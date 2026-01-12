# Quick Testing Steps

## 1. First, Update Terraform State (if needed)

```powershell
cd terraform-files
terraform refresh  # Refresh state with latest outputs
terraform output   # Verify all outputs are available
```

If `redis_endpoint`, `db_endpoint`, or `opensearch_endpoint` are missing, run:
```powershell
terraform apply  # This will update outputs
```

## 2. SSH into EC2 Instance

```powershell
# Get EC2 IP from Terraform output
cd terraform-files
$EC2_IP = "54.205.187.126"  # From terraform output, or get dynamically:
# $EC2_IP = (terraform output -raw availability_api_url) -replace 'http://', '' -replace ':30001', ''

# SSH into instance (adjust key path as needed)
ssh -i k3s-key ubuntu@$EC2_IP
```

## 3. Quick Health Checks (From EC2 Instance)

Once SSH'd in, run these commands:

```bash
# 1. Check if k3s is running
sudo systemctl status k3s | head -5

# 2. Check all pods status
k3s kubectl get pods

# 3. Check deployments
k3s kubectl get deployments

# 4. Check ConfigMap exists and has values
k3s kubectl get configmap app-config -o yaml

# 5. Check pods are running (should see all 3 pods in Running state)
k3s kubectl get pods -o wide

# 6. Check Availability Service logs
k3s kubectl logs deployment/availability-app --tail=20

# 7. Check Order Service logs
k3s kubectl logs deployment/order-app --tail=20

# 8. Check Fulfillment Worker logs
k3s kubectl logs deployment/fulfillment-worker --tail=20
```

## 4. Test Health Endpoints (From Local Machine)

```powershell
# Test Availability Service
curl http://54.205.187.126:30001/

# Test Order Service
curl http://54.205.187.126:30002/

# Expected response: {"status":"healthy","service":"availability-service"} or order-service
```

## 5. Check Resource Usage (From EC2)

```bash
# Check system resources
free -h
df -h

# Check pod resource usage (if metrics available)
k3s kubectl top pods

# Check for any errors
k3s kubectl get events --sort-by='.lastTimestamp' | tail -10
```

## 6. Verify Environment Variables

```bash
# Get pod names
AVAIL_POD=$(k3s kubectl get pods -l app=availability -o jsonpath='{.items[0].metadata.name}')
ORDER_POD=$(k3s kubectl get pods -l app=order -o jsonpath='{.items[0].metadata.name}')
FULFILL_POD=$(k3s kubectl get pods -l app=fulfillment -o jsonpath='{.items[0].metadata.name}')

# Check environment variables
echo "=== Availability Service Env ==="
k3s kubectl exec $AVAIL_POD -- env | grep -E "REDIS|OPENSEARCH|AWS"

echo "=== Order Service Env ==="
k3s kubectl exec $ORDER_POD -- env | grep -E "SQS|AWS"

echo "=== Fulfillment Worker Env ==="
k3s kubectl exec $FULFILL_POD -- env | grep -E "SQS|DB|AWS"
```

## Expected Results

✅ **All pods should be in `Running` state**  
✅ **ConfigMap should have actual endpoint values (not placeholders)**  
✅ **Health checks should return 200 OK**  
✅ **No errors in logs about connection failures**  
✅ **Resource usage should be reasonable (no OOM kills)**

## Common Issues & Fixes

### If pods are in `ImagePullBackOff`:
```bash
# Check ECR secret
k3s kubectl get secret ecr-secret
# If missing, it will be created by user_data.sh when instance is provisioned
```

### If pods are `CrashLoopBackOff`:
```bash
# Check logs for errors
k3s kubectl logs <pod-name>
# Check describe for more details
k3s kubectl describe pod <pod-name>
```

### If ConfigMap has wrong values:
The ConfigMap is created by `user_data.sh` automatically. If values are wrong:
1. Ensure Terraform state is up to date
2. Re-provision EC2 instance: `terraform apply -replace=aws_instance.app_server`

### If services can't connect:
```bash
# Test connectivity from pod
k3s kubectl exec -it <pod-name> -- sh
# Inside pod:
ping <endpoint>
# Exit pod with 'exit'
```
