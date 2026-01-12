# Kubernetes Deployment Fixes - Summary

## Problems Identified

### 1. **Resource Constraints (t3.micro)**
- **Issue**: t3.micro instance has only 1GB RAM, which is insufficient for k3s + 3 containers
- **Symptom**: Containers get stuck, system becomes unresponsive, OOM kills
- **Solution**: 
  - Added resource limits (128Mi-256Mi per container)
  - Added 2GB swap file in user_data.sh
  - Optimized k3s configuration for low-resource environments
  - Disabled unnecessary k3s components (traefik, servicelb)

### 2. **Missing Resource Limits**
- **Issue**: No CPU/memory limits in Kubernetes deployments
- **Symptom**: Containers consume all available resources, causing system instability
- **Solution**: Added resource requests and limits to all deployments:
  - Requests: 128Mi memory, 100m CPU
  - Limits: 256Mi memory, 500m CPU

### 3. **Missing Environment Variables**
- **Issue**: Incomplete environment variable configuration
- **Symptoms**: 
  - Order service: Missing `SQS_QUEUE_URL`
  - Fulfillment worker: Missing `DB_NAME`, `DB_USER`, `DB_PASS`
  - Availability service: Missing `OPENSEARCH_URL` and `REDIS_HOST` in rapid-d.yaml
- **Solution**: Added all required environment variables in user_data.sh deployment YAML

### 4. **No Health Checks**
- **Issue**: No liveness/readiness probes configured
- **Symptom**: Kubernetes can't detect if containers are stuck or unhealthy
- **Solution**: Added health checks for all services:
  - HTTP probes for availability and order services
  - Process check for fulfillment worker

### 5. **Missing Database Credentials**
- **Issue**: Fulfillment worker needs DB credentials but they weren't configured
- **Solution**: Created Kubernetes Secret with DB credentials and referenced in deployment

### 6. **No Health Check Endpoint**
- **Issue**: Order service didn't have a root health check endpoint
- **Solution**: Added `@app.get("/")` health check endpoint

## Files Modified

### 1. `k/rapid-d.yaml`
- Added resource limits and requests
- Added health checks (liveness/readiness probes)
- Added ConfigMap and Secret definitions
- Added missing environment variables

### 2. `terraform-files/user_data.sh`
- Added ConfigMap and Secret creation
- Updated deployment YAML with resource limits
- Added health checks
- Added all missing environment variables
- Optimized k3s installation for low-resource environment
- Added deployment readiness checks

### 3. `order-service/main.py`
- Added health check endpoint at root path

### 4. `availability-service/Dockerfile`
- Optimized uvicorn to use 1 worker (reduces memory usage)

### 5. `order-service/Dockerfile`
- Optimized uvicorn to use 1 worker (reduces memory usage)

### 6. `terraform-files/compute.tf`
- Added comment about instance size limitations

## Recommendations

### Short-term (Current Setup)
1. **Monitor resource usage**: Use `kubectl top pods` to monitor actual usage
2. **Watch for OOM kills**: Check pod logs for OOM kill messages
3. **Consider increasing swap**: Current 2GB swap may need to be increased if issues persist

### Long-term (Production)
1. **Upgrade instance type**: 
   - Minimum: t3.small (2GB RAM)
   - Recommended: t3.medium (4GB RAM)
2. **Add monitoring**: Set up Prometheus/Grafana to track resource usage
3. **Implement autoscaling**: Consider HPA (Horizontal Pod Autoscaler) for services
4. **Use managed Kubernetes**: Consider EKS instead of k3s for production

## Testing the Fixes

After applying these changes:

1. **Update Terraform outputs** (to get latest endpoint values):
   ```bash
   cd terraform-files
   terraform apply  # This will update outputs.tf with new outputs
   terraform output  # Verify all outputs are available
   ```

2. **Rebuild Docker images**:
   ```bash
   docker build -t availability-service:latest ./availability-service
   docker build -t order-service:latest ./order-service
   docker build -t fulfillment-worker:latest ./fulfillment-worker
   ```

3. **Push to ECR** (if using ECR):
   ```bash
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 905418449359.dkr.ecr.us-east-1.amazonaws.com
   docker tag availability-service:latest 905418449359.dkr.ecr.us-east-1.amazonaws.com/availability-service:latest
   docker tag order-service:latest 905418449359.dkr.ecr.us-east-1.amazonaws.com/order-service:latest
   docker tag fulfillment-worker:latest 905418449359.dkr.ecr.us-east-1.amazonaws.com/fulfillment-worker:latest
   docker push 905418449359.dkr.ecr.us-east-1.amazonaws.com/availability-service:latest
   docker push 905418449359.dkr.ecr.us-east-1.amazonaws.com/order-service:latest
   docker push 905418449359.dkr.ecr.us-east-1.amazonaws.com/fulfillment-worker:latest
   ```

4. **Apply Terraform changes** (if infrastructure needs updating):
   ```bash
   cd terraform-files
   terraform apply
   ```
   
   **Note**: The `user_data.sh` script automatically creates the ConfigMap and Secret from Terraform variables when the EC2 instance is created/updated.

5. **If manually updating rapid-d.yaml** (alternative to user_data.sh):
   ```bash
   # Linux/Mac
   cd terraform-files
   ./generate-configmap.sh > ../k/configmap-generated.yaml
   
   # Windows PowerShell
   cd terraform-files
   .\generate-configmap.ps1 | Out-File ..\k\configmap-generated.yaml
   
   # Then apply the generated ConfigMap
   kubectl apply -f k/configmap-generated.yaml
   kubectl apply -f k/rapid-d.yaml
   ```

6. **Check pod status** (SSH into EC2 instance):
   ```bash
   ssh -i k3s-key.pem ubuntu@<EC2_PUBLIC_IP>
   k3s kubectl get pods
   k3s kubectl describe pod <pod-name>
   k3s kubectl logs <pod-name>
   k3s kubectl get configmap app-config -o yaml
   k3s kubectl get secret db-credentials -o yaml
   ```

7. **Monitor resources**:
   ```bash
   k3s kubectl top pods
   free -h  # Check system memory
   df -h  # Check disk space
   ```

## Key Configuration Values

- **Container Memory**: 128Mi request, 256Mi limit
- **Container CPU**: 100m request, 500m limit
- **Swap File**: 2GB
- **Max Pods**: 10 (k3s configuration)
- **Eviction Threshold**: 100Mi hard, 200Mi soft

## Troubleshooting

If containers still get stuck:

1. **Check pod events**: `k3s kubectl describe pod <pod-name>`
2. **Check system resources**: `free -h`, `df -h`
3. **Check k3s logs**: `journalctl -u k3s -f`
4. **Check container logs**: `k3s kubectl logs <pod-name>`
5. **Verify environment variables**: `k3s kubectl exec <pod-name> -- env`
