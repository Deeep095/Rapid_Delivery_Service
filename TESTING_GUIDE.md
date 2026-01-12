# Testing Guide - Rapid Delivery Service Kubernetes Deployment

## Prerequisites Check

Before testing, ensure you have:
- ✅ AWS CLI configured with credentials
- ✅ Terraform installed
- ✅ Docker installed (for building images if needed)
- ✅ SSH access to EC2 instance (k3s-key.pem)

## Step 1: Verify Terraform State

```bash
cd terraform-files
terraform output
```

Expected outputs:
- `availability_api_url`
- `order_api_url`
- `sqs_queue_url`
- `redis_endpoint` (if updated)
- `db_endpoint` (if updated)
- `opensearch_endpoint` (if updated)

## Step 2: Rebuild and Push Docker Images (if code changed)

If you've modified any service code, rebuild and push images:

```bash
# Set variables
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=905418449359
export ECR_REGISTRY=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Login to ECR
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# Build and push Availability Service
docker build -t ${ECR_REGISTRY}/availability-service:latest ./availability-service
docker push ${ECR_REGISTRY}/availability-service:latest

# Build and push Order Service
docker build -t ${ECR_REGISTRY}/order-service:latest ./order-service
docker push ${ECR_REGISTRY}/order-service:latest

# Build and push Fulfillment Worker
docker build -t ${ECR_REGISTRY}/fulfillment-worker:latest ./fulfillment-worker
docker push ${ECR_REGISTRY}/fulfillment-worker:latest
```

## Step 3: Apply Terraform (if infrastructure changed)

```bash
cd terraform-files

# Plan to see what will change
terraform plan

# Apply changes (if user_data.sh was modified, this will recreate/reconfigure EC2)
terraform apply
```

**Note**: If `user_data.sh` was modified, Terraform might need to recreate the EC2 instance. Check the plan output.

## Step 4: SSH into EC2 Instance

```bash
# Get EC2 public IP from Terraform output
cd terraform-files
EC2_IP=$(terraform output -raw availability_api_url | sed 's|http://||' | sed 's|:30001||')
echo "EC2 IP: $EC2_IP"

# SSH into instance (Windows PowerShell)
ssh -i terraform-files/k3s-key ubuntu@$EC2_IP

# Or if using .pem file
ssh -i k3s-key.pem ubuntu@<EC2_PUBLIC_IP>
```

## Step 5: Check k3s Cluster Status

Once SSH'd into the EC2 instance:

```bash
# Check k3s service status
sudo systemctl status k3s

# Check k3s is running
k3s kubectl get nodes

# Check all pods across all namespaces
k3s kubectl get pods -A

# Check deployments
k3s kubectl get deployments

# Check services
k3s kubectl get services
```

**Expected output**:
- All pods should be in `Running` state
- Deployments: `availability-app`, `order-app`, `fulfillment-worker`
- Services: `availability-service`, `order-service`

## Step 6: Verify ConfigMap and Secret

```bash
# Check ConfigMap exists and has correct values
k3s kubectl get configmap app-config -o yaml

# Verify endpoints are correct (should match your Terraform outputs)
k3s kubectl get configmap app-config -o jsonpath='{.data.redis-endpoint}'
k3s kubectl get configmap app-config -o jsonpath='{.data.db-endpoint}'
k3s kubectl get configmap app-config -o jsonpath='{.data.sqs-queue-url}'

# Check Secret exists
k3s kubectl get secret db-credentials -o yaml
```

## Step 7: Check Pod Status and Logs

```bash
# Get detailed pod status
k3s kubectl get pods -o wide

# Check specific pod status
k3s kubectl describe pod <pod-name>

# Check Availability Service logs
k3s kubectl logs deployment/availability-app

# Check Order Service logs
k3s kubectl logs deployment/order-app

# Check Fulfillment Worker logs
k3s kubectl logs deployment/fulfillment-worker

# Follow logs in real-time
k3s kubectl logs -f deployment/availability-app
```

**Things to check in logs**:
- No connection errors to Redis, DB, or SQS
- Services started successfully
- Health check endpoints responding

## Step 8: Check Pod Environment Variables

```bash
# Check environment variables in Availability Service pod
AVAIL_POD=$(k3s kubectl get pods -l app=availability -o jsonpath='{.items[0].metadata.name}')
k3s kubectl exec $AVAIL_POD -- env | grep -E "REDIS|OPENSEARCH|AWS"

# Check environment variables in Order Service pod
ORDER_POD=$(k3s kubectl get pods -l app=order -o jsonpath='{.items[0].metadata.name}')
k3s kubectl exec $ORDER_POD -- env | grep -E "SQS|AWS"

# Check environment variables in Fulfillment Worker pod
FULFILL_POD=$(k3s kubectl get pods -l app=fulfillment -o jsonpath='{.items[0].metadata.name}')
k3s kubectl exec $FULFILL_POD -- env | grep -E "SQS|DB|AWS"
```

## Step 9: Test Health Check Endpoints

```bash
# Test Availability Service health check (from within EC2 or from external)
curl http://localhost:30001/
# Or from external:
curl http://$(terraform output -raw availability_api_url | sed 's|http://||' | sed 's|:30001||'):30001/

# Test Order Service health check
curl http://localhost:30002/
# Or from external:
curl http://$(terraform output -raw order_api_url | sed 's|http://||' | sed 's|:30002||'):30002/

# Expected response:
# {"status":"healthy","service":"availability-service"} or {"status":"healthy","service":"order-service"}
```

## Step 10: Monitor Resource Usage

```bash
# Check pod resource usage (if metrics-server is available)
k3s kubectl top pods

# Check node resource usage
k3s kubectl top node

# Check system memory
free -h

# Check disk space
df -h

# Check swap usage
swapon --show
```

## Step 11: Test Functional Endpoints

### Test Availability Service

```bash
# From EC2 or external machine
AVAIL_URL=$(terraform output -raw availability_api_url)

# Test availability check
curl "${AVAIL_URL}/availability?item_id=item1&lat=40.7128&lon=-74.0060"
```

### Test Order Service

```bash
# From EC2 or external machine
ORDER_URL=$(terraform output -raw order_api_url)

# Test order placement
curl -X POST "${ORDER_URL}/order" \
  -H "Content-Type: application/json" \
  -d '{
    "customer_id": "test-customer-1",
    "items": [
      {
        "item_id": "item1",
        "warehouse_id": "warehouse1",
        "quantity": 2
      }
    ]
  }'
```

## Step 12: Verify Fulfillment Worker Processing

```bash
# Check if fulfillment worker is processing messages
k3s kubectl logs deployment/fulfillment-worker --tail=50

# Check for SQS polling activity
k3s kubectl logs deployment/fulfillment-worker | grep -i "polling\|processing\|order"

# Check SQS queue messages (from AWS CLI)
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/905418449359/order-fulfillment-queue \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible
```

## Step 13: Check for Common Issues

```bash
# Check if pods are restarting (CrashLoopBackOff)
k3s kubectl get pods | grep -E "Error|CrashLoop|Pending|ImagePullBackOff"

# Check pod events for errors
k3s kubectl get events --sort-by='.lastTimestamp' | tail -20

# Check k3s service logs
sudo journalctl -u k3s -n 100 --no-pager

# Check if resources are constrained
k3s kubectl describe nodes | grep -A 5 "Allocated resources"
```

## Troubleshooting Commands

### If pods are stuck in Pending:
```bash
k3s kubectl describe pod <pod-name> | grep -A 10 "Events"
```

### If pods are in ImagePullBackOff:
```bash
# Verify ECR secret exists
k3s kubectl get secret ecr-secret

# Check if secret is correctly configured
k3s kubectl get secret ecr-secret -o yaml
```

### If services can't connect to databases:
```bash
# Test connectivity from pod
k3s kubectl exec -it <pod-name> -- bash
# Inside pod:
ping <redis-endpoint>
ping <db-endpoint>
telnet <redis-endpoint> 6379
telnet <db-endpoint> 5432
```

### If resource limits are too tight:
```bash
# Check actual usage vs limits
k3s kubectl top pods
# If pods are OOMKilled, increase limits in rapid-d.yaml
```

## Success Criteria

✅ All pods are in `Running` state  
✅ ConfigMap has correct endpoint values  
✅ Secret exists with DB password  
✅ Health check endpoints return `200 OK`  
✅ No errors in pod logs  
✅ Resource usage is within limits (no OOM kills)  
✅ Services can connect to Redis, DB, and SQS  
✅ Fulfillment worker is polling SQS successfully  

## Quick Test Script

Save this as `quick-test.sh`:

```bash
#!/bin/bash
set -e

echo "=== Testing Rapid Delivery Service ==="

# Get EC2 IP
EC2_IP=$(cd terraform-files && terraform output -raw availability_api_url | sed 's|http://||' | sed 's|:30001||')

echo "1. Testing Availability Service..."
curl -f "http://${EC2_IP}:30001/" || echo "❌ Availability Service failed"

echo "2. Testing Order Service..."
curl -f "http://${EC2_IP}:30002/" || echo "❌ Order Service failed"

echo "=== Tests Complete ==="
```

Run: `bash quick-test.sh`
