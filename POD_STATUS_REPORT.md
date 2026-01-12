# Pod Status Report - Current Issues Found

## Current Pod Status

```
NAME                                 READY   STATUS             RESTARTS   AGE
availability-app-778d8795ff-f2r8m    1/1     Running           0          30m ✅
fulfillment-worker-8cc648fc9-95mch   0/1     CrashLoopBackOff  8          30m ❌
order-app-577b7958d7-zk5j9           0/1     CrashLoopBackOff  11         30m ❌
```

## Issues Found

### 1. ✅ Availability Service - WORKING
- Status: Running successfully
- No issues detected
- ConfigMap has correct Redis endpoint: `rapid-redis.pqqgpc.0001.use1.cache.amazonaws.com`

### 2. ❌ Order Service - CRASHING
**Issue**: Liveness probe failing with 404 error
- **Root Cause**: The Docker image was built BEFORE we added the health check endpoint (`@app.get("/")`) to `order-service/main.py`
- **Error**: `HTTP probe failed with statuscode: 404`
- **Solution**: Rebuild and push the order-service Docker image with the updated code

**Fix Required**:
```bash
cd order-service
docker build -t 905418449359.dkr.ecr.us-east-1.amazonaws.com/order-service:latest .
docker push 905418449359.dkr.ecr.us-east-1.amazonaws.com/order-service:latest

# Then restart the deployment
k3s kubectl rollout restart deployment/order-app
```

### 3. ❌ Fulfillment Worker - CRASHING
**Issue**: Container crashing after startup
- **Root Cause**: Likely missing environment variables or connection issues
- **Logs show**: 
  - Successfully starting with SQS queue URL
  - Python deprecation warning (not critical)
  - Then crashes

**Potential Issues**:
- Missing `SQS_QUEUE_URL` environment variable (but ConfigMap shows it exists)
- Missing `DB_HOST` environment variable (but ConfigMap shows it exists)  
- Connection failures to DB or SQS
- The user_data.sh deployment might not be setting environment variables correctly

**Check Required**: Verify environment variables are being injected from ConfigMap properly in the user_data.sh deployment.

## ConfigMap Status ✅

The ConfigMap has correct values:
```yaml
redis-endpoint: rapid-redis.pqqgpc.0001.use1.cache.amazonaws.com
db-endpoint: rapid-delivery-db.c6t2s662e2x0.us-east-1.rds.amazonaws.com
sqs-queue-url: https://sqs.us-east-1.amazonaws.com/905418449359/order-fulfillment-queue
```

## Secret Status ✅

The Secret exists with correct DB password.

## Immediate Actions Required

1. **Rebuild Order Service Docker Image** (highest priority)
   - The code has the health check endpoint
   - But the running Docker image doesn't
   - Rebuild and push to ECR
   - Restart deployment

2. **Check Fulfillment Worker Environment Variables**
   - Verify deployment YAML in user_data.sh is correctly referencing ConfigMap
   - Check if variables are actually being set in the pod

3. **Debug Fulfillment Worker**
   - Get more detailed logs
   - Check if DB/SQS connections are working
   - Verify IAM permissions for SQS access

## Commands to Run

### To check current deployment configuration:
```bash
ssh -i terraform-files/k3s-key ubuntu@54.205.187.126
sudo k3s kubectl get deployment order-app -o yaml | grep -A 30 env:
sudo k3s kubectl get deployment fulfillment-worker -o yaml | grep -A 30 env:
```

### To check environment variables in running pods:
```bash
# Order service (if it starts)
ORDER_POD=$(sudo k3s kubectl get pods -l app=order -o jsonpath='{.items[0].metadata.name}')
sudo k3s kubectl exec $ORDER_POD -- env

# Fulfillment worker
FULFILL_POD=$(sudo k3s kubectl get pods -l app=fulfillment -o jsonpath='{.items[0].metadata.name}')
sudo k3s kubectl exec $FULFILL_POD -- env
```

### To rebuild and redeploy:
```bash
# 1. Rebuild Docker images (from local machine)
cd order-service
docker build -t 905418449359.dkr.ecr.us-east-1.amazonaws.com/order-service:latest .
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 905418449359.dkr.ecr.us-east-1.amazonaws.com
docker push 905418449359.dkr.ecr.us-east-1.amazonaws.com/order-service:latest

cd ../fulfillment-worker
docker build -t 905418449359.dkr.ecr.us-east-1.amazonaws.com/fulfillment-worker:latest .
docker push 905418449359.dkr.ecr.us-east-1.amazonaws.com/fulfillment-worker:latest

# 2. Restart deployments (from EC2)
ssh -i terraform-files/k3s-key ubuntu@54.205.187.126
sudo k3s kubectl rollout restart deployment/order-app
sudo k3s kubectl rollout restart deployment/fulfillment-worker
sudo k3s kubectl get pods -w
```
