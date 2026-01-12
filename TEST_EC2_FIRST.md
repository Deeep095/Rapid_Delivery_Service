# Testing EC2 Instance First (Before DBs are Ready)

## Overview

Since you want to test the EC2/k3s setup first without waiting for OpenSearch, Redis, and RDS to be fully provisioned, here's how to do it:

## Strategy

1. **Terraform will create EC2 instance** with `user_data.sh` that:
   - Installs k3s
   - Creates ConfigMap with endpoint values (even if DBs aren't ready yet)
   - Deploys pods

2. **Pods will start** but may fail to connect to DBs initially (that's OK for testing)

3. **You can verify**:
   - k3s is running
   - Pods are being created
   - ConfigMap/Secret are created
   - Images are being pulled

## Step 1: Apply Terraform (EC2 Only)

You can apply Terraform in stages. For now, just ensure EC2 is created:

```bash
cd terraform-files

# Plan to see what will be created
terraform plan

# Apply (this will create EC2, but DBs may take time)
terraform apply
```

**Note**: The `user_data.sh` will run even if DBs aren't ready. It will use whatever endpoint values Terraform provides (which may be empty/placeholder if DBs aren't created yet).

## Step 2: SSH and Check EC2 Setup

```bash
# Get EC2 IP
cd terraform-files
EC2_IP=$(terraform output -raw availability_api_url 2>&1 | sed 's|http://||' | sed 's|:30001||')
echo "EC2 IP: $EC2_IP"

# SSH into instance
ssh -i k3s-key ubuntu@$EC2_IP
```

## Step 3: Check k3s and Pods

Once SSH'd in:

```bash
# 1. Check k3s is running
sudo systemctl status k3s

# 2. Check nodes
sudo k3s kubectl get nodes

# 3. Check all pods
sudo k3s kubectl get pods

# 4. Check ConfigMap (see what values were set)
sudo k3s kubectl get configmap app-config -o yaml

# 5. Check deployments
sudo k3s kubectl get deployments

# 6. Check services
sudo k3s kubectl get services
```

## Step 4: Check Pod Logs

```bash
# Check Availability Service logs
sudo k3s kubectl logs deployment/availability-app --tail=30

# Check Order Service logs
sudo k3s kubectl logs deployment/order-app --tail=30

# Check Fulfillment Worker logs
sudo k3s kubectl logs deployment/fulfillment-worker --tail=30
```

## Expected Behavior

### If DBs are NOT ready yet:
- ✅ k3s should be running
- ✅ Pods should be created (may be in CrashLoopBackOff or Error state)
- ✅ ConfigMap should exist (may have placeholder/empty values)
- ⚠️ Pods will fail to connect to DBs (expected)

### If DBs ARE ready:
- ✅ All pods should be Running
- ✅ ConfigMap should have actual endpoint values
- ✅ Services should be able to connect

## Check ConfigMap Values

```bash
# See what endpoint values were set
sudo k3s kubectl get configmap app-config -o jsonpath='{.data.redis-endpoint}' && echo
sudo k3s kubectl get configmap app-config -o jsonpath='{.data.db-endpoint}' && echo
sudo k3s kubectl get configmap app-config -o jsonpath='{.data.sqs-queue-url}' && echo
sudo k3s kubectl get configmap app-config -o jsonpath='{.data.opensearch-endpoint}' && echo
```

## Update ConfigMap After DBs are Ready

If DBs become ready later, you can update the ConfigMap:

```bash
# Update ConfigMap with actual values
sudo k3s kubectl create configmap app-config \
  --from-literal=redis-endpoint="<actual-redis-endpoint>" \
  --from-literal=db-endpoint="<actual-db-endpoint>" \
  --from-literal=sqs-queue-url="<actual-sqs-url>" \
  --from-literal=opensearch-endpoint="https://<actual-opensearch-endpoint>" \
  --dry-run=client -o yaml | sudo k3s kubectl apply -f -

# Restart deployments to pick up new values
sudo k3s kubectl rollout restart deployment/availability-app
sudo k3s kubectl rollout restart deployment/order-app
sudo k3s kubectl rollout restart deployment/fulfillment-worker
```

## Quick Status Check Script

Save this as `check-ec2-status.sh`:

```bash
#!/bin/bash
echo "=== k3s Status ==="
sudo systemctl is-active k3s && echo "✅ k3s is running" || echo "❌ k3s is not running"

echo -e "\n=== Pod Status ==="
sudo k3s kubectl get pods

echo -e "\n=== ConfigMap ==="
sudo k3s kubectl get configmap app-config -o yaml | grep -A 5 "data:"

echo -e "\n=== Recent Events ==="
sudo k3s kubectl get events --sort-by='.lastTimestamp' | tail -5
```

Run: `bash check-ec2-status.sh`

## Troubleshooting

### If pods are in ImagePullBackOff:
- Check ECR secret: `sudo k3s kubectl get secret ecr-secret`
- Verify images exist in ECR
- Check IAM permissions for ECR access

### If ConfigMap has placeholder values:
- This is expected if DBs aren't ready
- Update ConfigMap once DBs are ready (see above)

### If pods keep crashing:
- Check logs: `sudo k3s kubectl logs <pod-name>`
- Check events: `sudo k3s kubectl describe pod <pod-name>`
- May be expected if DBs aren't accessible yet

## Next Steps

Once EC2/k3s is verified working:
1. Wait for DBs to be fully provisioned
2. Update ConfigMap with actual endpoint values
3. Restart deployments
4. Verify all pods are Running
