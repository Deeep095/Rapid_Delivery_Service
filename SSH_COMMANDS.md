# SSH Commands to Check Pods on EC2

## Quick SSH Command

```powershell
# SSH into EC2 instance
ssh -i terraform-files/k3s-key ubuntu@54.205.187.126
```

Or if you want to get the IP dynamically:
```powershell
cd terraform-files
$EC2_IP = (terraform output -raw availability_api_url) -replace 'http://', '' -replace ':30001', ''
ssh -i k3s-key ubuntu@$EC2_IP
```

## Once SSH'd In - Check Pod Status

```bash
# 1. Check all pods status
sudo k3s kubectl get pods

# 2. Get detailed pod status with wide output
sudo k3s kubectl get pods -o wide

# 3. Check pods with more details (restarts, age, etc.)
sudo k3s kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp
```

## Check Specific Pod Details

```bash
# Check order-app pod details
sudo k3s kubectl describe pod -l app=order

# Check fulfillment-worker pod details  
sudo k3s kubectl describe pod -l app=fulfillment

# Check availability-app pod details
sudo k3s kubectl describe pod -l app=availability
```

## Check Pod Logs

```bash
# Order Service logs
sudo k3s kubectl logs deployment/order-app --tail=50

# Fulfillment Worker logs
sudo k3s kubectl logs deployment/fulfillment-worker --tail=50

# Availability Service logs
sudo k3s kubectl logs deployment/availability-app --tail=50

# Follow logs in real-time
sudo k3s kubectl logs -f deployment/order-app
```

## Check Deployment Status

```bash
# Get all deployments
sudo k3s kubectl get deployments

# Check deployment details
sudo k3s kubectl describe deployment order-app
sudo k3s kubectl describe deployment fulfillment-worker
sudo k3s kubectl describe deployment availability-app

# Check rollout status
sudo k3s kubectl rollout status deployment/order-app
sudo k3s kubectl rollout status deployment/fulfillment-worker
```

## Check Environment Variables

```bash
# Get pod names first
AVAIL_POD=$(sudo k3s kubectl get pods -l app=availability -o jsonpath='{.items[0].metadata.name}')
ORDER_POD=$(sudo k3s kubectl get pods -l app=order -o jsonpath='{.items[0].metadata.name}')
FULFILL_POD=$(sudo k3s kubectl get pods -l app=fulfillment -o jsonpath='{.items[0].metadata.name}')

# Check environment variables for each service
echo "=== Availability Service Env ==="
sudo k3s kubectl exec $AVAIL_POD -- env | grep -E "REDIS|OPENSEARCH|AWS"

echo "=== Order Service Env ==="
sudo k3s kubectl exec $ORDER_POD -- env | grep -E "SQS|AWS"

echo "=== Fulfillment Worker Env ==="
sudo k3s kubectl exec $FULFILL_POD -- env | grep -E "SQS|DB|AWS"
```

## Check ConfigMap and Secret

```bash
# Check ConfigMap
sudo k3s kubectl get configmap app-config -o yaml

# Check Secret
sudo k3s kubectl get secret db-credentials -o yaml

# Verify specific values
sudo k3s kubectl get configmap app-config -o jsonpath='{.data.redis-endpoint}'
sudo k3s kubectl get configmap app-config -o jsonpath='{.data.db-endpoint}'
sudo k3s kubectl get configmap app-config -o jsonpath='{.data.sqs-queue-url}'
```

## Check Resource Usage

```bash
# Check system resources
free -h
df -h

# Check pod resource usage (if metrics available)
sudo k3s kubectl top pods

# Check node resource usage
sudo k3s kubectl top node
```

## Check Events and Errors

```bash
# Get recent events
sudo k3s kubectl get events --sort-by='.lastTimestamp' | tail -20

# Check specific pod events
sudo k3s kubectl describe pod <pod-name> | grep -A 20 Events
```

## Restart Deployments (if needed)

```bash
# Restart a specific deployment (will pull latest image)
sudo k3s kubectl rollout restart deployment/order-app
sudo k3s kubectl rollout restart deployment/fulfillment-worker

# Watch pods restart
sudo k3s kubectl get pods -w
```

## All-in-One Status Check Command

```bash
echo "=== POD STATUS ===" && \
sudo k3s kubectl get pods && \
echo -e "\n=== DEPLOYMENTS ===" && \
sudo k3s kubectl get deployments && \
echo -e "\n=== SERVICES ===" && \
sudo k3s kubectl get services && \
echo -e "\n=== RECENT EVENTS ===" && \
sudo k3s kubectl get events --sort-by='.lastTimestamp' | tail -10
```

## Expected Healthy State

After rebuilding images and restarting, you should see:
```
NAME                                 READY   STATUS    RESTARTS   AGE
availability-app-xxx-xxx             1/1     Running   0          Xm
order-app-xxx-xxx                    1/1     Running   0          Xm
fulfillment-worker-xxx-xxx           1/1     Running   0          Xm
```

All should show:
- ✅ STATUS: `Running` (not CrashLoopBackOff or Error)
- ✅ READY: `1/1` (not 0/1)
- ✅ RESTARTS: Low number or 0
