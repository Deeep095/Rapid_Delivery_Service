# Fix: Ports 30001-30002 Not Accessible

## Issue Found

The security group doesn't allow external access to ports 30001-30002 (Kubernetes NodePort services).

## Status

✅ **Availability Service**: Running and working on localhost  
❌ **Order Service**: CrashLoopBackOff (Docker image needs rebuild with health check)  
❌ **Fulfillment Worker**: CrashLoopBackOff (Docker image needs rebuild with procps)  
❌ **External Access**: Blocked by security group (ports 30001-30002 not open)

## Fix Applied

Added security group rules to allow ports 30001-30002 in `terraform-files/databases.tf`.

## Next Steps

### 1. Apply Security Group Fix

```powershell
cd terraform-files
terraform plan  # Review changes
terraform apply  # Apply security group update
```

**Note**: This only updates the security group, it won't recreate the EC2 instance.

### 2. Test After Security Group Update

```powershell
# Test Availability Service (should work now)
curl http://54.174.229.10:30001/

# Test Order Service (will fail until Docker image is rebuilt)
curl http://54.174.229.10:30002/
```

### 3. Rebuild Docker Images (for order-app and fulfillment-worker)

The order service is crashing because the Docker image doesn't have the health check endpoint. You need to rebuild and push:

```powershell
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 905418449359.dkr.ecr.us-east-1.amazonaws.com

# Rebuild and push Order Service
cd order-service
docker build -t 905418449359.dkr.ecr.us-east-1.amazonaws.com/order-service:latest .
docker push 905418449359.dkr.ecr.us-east-1.amazonaws.com/order-service:latest

# Rebuild and push Fulfillment Worker (already has procps fix)
cd ..\fulfillment-worker
docker build -t 905418449359.dkr.ecr.us-east-1.amazonaws.com/fulfillment-worker:latest .
docker push 905418449359.dkr.ecr.us-east-1.amazonaws.com/fulfillment-worker:latest
```

### 4. Restart Deployments

```powershell
ssh -i terraform-files/k3s-key ubuntu@54.174.229.10
sudo k3s kubectl rollout restart deployment/order-app
sudo k3s kubectl rollout restart deployment/fulfillment-worker
sudo k3s kubectl get pods -w
```

## Summary

1. ✅ Security group rule added (needs `terraform apply`)
2. ⏳ Ports will be accessible after security group update
3. ⏳ Order service needs Docker image rebuild (health check endpoint)
4. ⏳ Fulfillment worker needs Docker image rebuild (procps installed)
