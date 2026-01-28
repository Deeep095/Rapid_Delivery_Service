# 🚀 COMPLETE AWS DEPLOYMENT GUIDE - 2 Instance Setup

## ✅ ORDER PLACEMENT FIXED

**Problem**: Order service was crashing because it tried to use SQS when `sqs = None` in local mode

**Solution Applied**:
- ✅ Fixed [order-service/main.py](../order-service/main.py) to handle local mode
- ✅ Changed endpoint from `/order` to `/orders` (consistent with API)
- ✅ Added order history endpoint `/orders/{customer_id}`
- ✅ **Order placement now working!**

Test it:
```bash
curl -X POST http://localhost:8001/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"test","items":[{"item_id":"apple","warehouse_id":"wh_rajapark","quantity":2}]}'
```

---

## 🏗️ COMPLETE AWS ARCHITECTURE (2 Instances)

### Why 2 EC2 Instances?
- **Problem**: 1 t3.micro (1GB RAM) + k3s + 3 services = Out of Memory crashes
- **Solution**: Split workload across 2 instances

| Instance | Services | RAM Usage | Purpose |
|----------|----------|-----------|---------|
| **API Server** | Availability + Order | ~600MB | Handles HTTP requests from Flutter |
| **Worker Server** | Fulfillment | ~400MB | Processes SQS queue in background |

**Still FREE TIER**: 2 × 750 hrs/month = 1500 hours (covers full month)

---

## 📋 DEPLOYMENT STEPS

### Step 1: Deploy Infrastructure

```bash
cd d:\Rapid_Delivery_Service\terraform-files

# Initialize Terraform (if first time)
terraform init

# Review what will be created
terraform plan

# Deploy everything
terraform apply -auto-approve
```

**Wait Time**: ~8-10 minutes for all services to provision

**What Gets Created**:
- ✅ 2 × EC2 t3.micro instances
- ✅ RDS PostgreSQL (publicly accessible)
- ✅ ElastiCache Redis (VPC-only)
- ✅ OpenSearch domain
- ✅ SQS queue
- ✅ Security groups with proper rules

### Step 2: Get AWS Endpoints

```bash
# View all outputs
terraform output

# Save for later use
terraform output > aws_endpoints.txt
```

**Expected Outputs**:
```
api_server_ip     = "XX.XX.XX.XX"
worker_server_ip  = "YY.YY.YY.YY"
rds_endpoint      = "rapid-delivery-db.xxxxx.us-east-1.rds.amazonaws.com:5432"
opensearch_url    = "https://search-xxxxx.us-east-1.es.amazonaws.com"
sqs_queue_url     = "https://sqs.us-east-1.amazonaws.com/xxxxx/order-fulfillment-queue"
```

### Step 3: Wait for EC2 Initialization

Both instances run startup scripts that:
1. Install k3s, Docker, AWS CLI
2. Pull images from ECR
3. Deploy services
4. Configure environment variables

**Check progress**:
```bash
# SSH into API server
ssh -i terraform-files/k3s-key ubuntu@XX.XX.XX.XX

# View startup log
sudo tail -f /var/log/cloud-init-output.log

# Check pods
kubectl get pods -A

# Should see:
# availability-app-xxxxx   Running
# order-app-xxxxx          Running
```

```bash
# SSH into Worker server
ssh -i terraform-files/k3s-key ubuntu@YY.YY.YY.YY

kubectl get pods -A

# Should see:
# fulfillment-worker-xxxxx Running
```

### Step 4: Seed the Database

**Important**: Even though RDS is in AWS, you can seed it from your laptop because it's publicly accessible!

```bash
# Update seed.py with AWS RDS endpoint
cd d:\Rapid_Delivery_Service

# Edit seed.py - change:
# DB_HOST = "rapid-delivery-db.xxxxx.us-east-1.rds.amazonaws.com"

python seed.py
```

**Alternative**: SSH into API server and run seed from there:
```bash
ssh -i k3s-key ubuntu@XX.XX.XX.XX

# Create seed script
cat > seed.py << 'EOF'
# Copy seed.py content here
EOF

# Install dependencies
sudo apt-get install -y python3-pip
pip3 install psycopg2-binary redis requests

# Run
python3 seed.py
```

### Step 5: Test the APIs

```bash
# Get API server IP
API_IP=$(cd terraform-files && terraform output -raw api_server_ip)

# Test availability service
curl http://$API_IP:30001/

# Test with location
curl "http://$API_IP:30001/availability?item_id=apple&lat=26.94&lon=75.84"

# Test order service
curl http://$API_IP:30002/

# Place an order
curl -X POST http://$API_IP:30002/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"mobile_user","items":[{"item_id":"apple","warehouse_id":"wh_rajapark","quantity":2}]}'
```

### Step 6: Update Flutter App

Edit [api_service.dart](../rapid_delivery_app/lib/api_service.dart):

```dart
static const String _awsServerIp = "XX.XX.XX.XX";  // Your API server IP
static const bool useAwsBackend = true;             // Enable AWS mode
```

### Step 7: Run Flutter App

```bash
cd d:\Rapid_Delivery_Service\rapid_delivery_app
flutter run -d chrome
```

**Test Flow**:
1. App opens → Location picker appears
2. Select "📍 LNMIIT Campus"
3. Products show stock levels
4. Add items to cart
5. Place order → Should succeed!
6. Check Orders tab → See order history

---

## 🔍 ARCHITECTURE DIAGRAM

```
┌─────────────────────────────────────────────────┐
│           FLUTTER APP (Your Laptop)             │
│              lib/api_service.dart               │
└──────────────────┬──────────────────────────────┘
                   │ HTTP
                   │
        ┌──────────┴──────────┐
        │                     │
        ▼                     ▼
┌──────────────────┐   ┌──────────────────┐
│  API SERVER EC2  │   │ WORKER SERVER EC2│
│  (t3.micro #1)   │   │  (t3.micro #2)   │
├──────────────────┤   ├──────────────────┤
│ • Availability   │   │ • Fulfillment    │
│   :30001         │   │   Worker         │
│ • Order          │   │                  │
│   :30002         │   │                  │
└────┬─────────┬───┘   └────┬─────────────┘
     │         │            │
     │         └────────────┼─────────┐
     │                      │         │
     ▼                      ▼         ▼
┌─────────────┐      ┌──────────┐  ┌─────────┐
│ OpenSearch  │      │   RDS    │  │   SQS   │
│ (geo-search)│      │(Postgres)│  │ (queue) │
│             │      │          │  │         │
└─────────────┘      └──────────┘  └─────────┘
                           ▲
     ┌─────────────────────┤
     │                     │
┌─────────┐         ┌──────────────┐
│  Redis  │         │ Worker reads │
│ (cache) │         │ & updates DB │
└─────────┘         └──────────────┘
```

---

## 📊 AWS SERVICES ACCESSIBILITY

| Service | Port | Public Access? | Notes |
|---------|------|----------------|-------|
| **RDS PostgreSQL** | 5432 | ✅ YES | Set `publicly_accessible = true` |
| **OpenSearch** | 443 | ✅ YES | IAM-based access policy |
| **SQS** | - | ✅ YES | AWS API (IAM credentials) |
| **ElastiCache Redis** | 6379 | ❌ NO | VPC-only, no public endpoint |

### Why Redis is VPC-Only
AWS ElastiCache Redis **does not support public access** for security reasons. This is by design.

**Solutions**:
1. ✅ **Current**: Run services on EC2 (they're in same VPC)
2. ❌ **Not viable**: Connect laptop directly to ElastiCache
3. 🔧 **Alternative**: Use AWS MemoryDB (supports public access, but costs more)
4. 🔧 **Alternative**: Set up VPN/Bastion host (complex)

---

## 💰 COST BREAKDOWN

### Free Tier (First 12 Months)
| Resource | Quantity | Free Tier | Cost |
|----------|----------|-----------|------|
| EC2 t3.micro | 2 | 750 hrs/mo each | $0 |
| RDS t3.micro | 1 | 750 hrs/mo | $0 |
| ElastiCache t2.micro | 1 | 750 hrs/mo | $0 |
| OpenSearch t3.small | 1 | 750 hrs/mo | $0 |
| EBS Storage | 40 GB | 30 GB free | $1 |
| SQS Requests | ~1M | 1M free | $0 |
| **TOTAL** | | | **~$1/month** |

### After Free Tier
| Resource | Monthly Cost |
|----------|--------------|
| 2 × EC2 t3.micro | ~$15 |
| RDS t3.micro | ~$15 |
| ElastiCache t2.micro | ~$12 |
| OpenSearch t3.small | ~$25 |
| **TOTAL** | **~$67/month** |

**Optimization Tips**:
- Use t2.micro instead of t3.micro (slightly cheaper)
- Stop instances when not testing
- Consider AWS Lightsail ($10-20/mo) for simpler setup

---

## 🐛 TROUBLESHOOTING

### Issue: EC2 instances not responding

**Check 1**: Instances running?
```bash
cd terraform-files
terraform show | grep "public_ip"
```

**Check 2**: Security group allows traffic?
```bash
# Check if ports 30001, 30002, 22 are open
aws ec2 describe-security-groups \
  --filters Name=group-name,Values=rapid-delivery-sg \
  --query 'SecurityGroups[0].IpPermissions'
```

**Check 3**: Pods running on EC2?
```bash
ssh -i k3s-key ubuntu@XX.XX.XX.XX "kubectl get pods -A"
```

### Issue: Database connection refused

**Check**: RDS security group allows EC2
```bash
# RDS should have security group rule allowing traffic from itself
# Already configured in databases.tf with: self = true
```

**Test**: Connect to RDS from laptop
```bash
# Install PostgreSQL client
# Windows: choco install postgresql
# Mac: brew install postgresql

# Test connection
psql -h rapid-delivery-db.xxxxx.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT 1;"
```

### Issue: Services can't access Redis

**Expected**: This is normal! Redis is VPC-only.

**Solution**: Services run on EC2 (inside VPC), so they CAN access Redis.

**Verify from EC2**:
```bash
ssh ubuntu@XX.XX.XX.XX
apt-get install -y redis-tools
redis-cli -h <REDIS_ENDPOINT> ping
# Should return: PONG
```

### Issue: Out of memory on EC2

**Check memory**:
```bash
ssh ubuntu@XX.XX.XX.XX
free -h
kubectl top nodes
kubectl top pods
```

**Solutions**:
- Instances already have 2GB swap enabled
- Resource limits set in Kubernetes manifests
- If still issues, reduce replicas or upgrade to t3.small

---

## 🔄 UPDATING THE DEPLOYMENT

### Update Service Code
1. Make changes to [availability-service/main.py](../availability-service/main.py)
2. Rebuild Docker image locally
3. Push to ECR
4. Restart pods on EC2

```bash
# Build and push (from your laptop)
cd availability-service
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com

docker build -t availability:latest .
docker tag availability:latest <ECR_URL>:latest
docker push <ECR_URL>:latest

# Restart on EC2
ssh ubuntu@XX.XX.XX.XX
kubectl rollout restart deployment/availability-app
```

### Update Terraform Configuration
```bash
cd terraform-files

# After making changes to .tf files
terraform plan
terraform apply
```

---

## 📈 SCALING UP (Future)

When you outgrow free tier:

### Option 1: Bigger EC2 Instances
```terraform
instance_type = "t3.small"  # 2GB RAM - $15/mo
# or
instance_type = "t3.medium" # 4GB RAM - $30/mo
```

### Option 2: Auto-Scaling
```terraform
resource "aws_autoscaling_group" "api_servers" {
  min_size = 1
  max_size = 3
  desired_capacity = 1
  # ... configuration
}
```

### Option 3: AWS ECS/Fargate
Replace k3s with managed container service:
- No server management
- Pay per second of use
- Better scaling

---

## 🎓 NEXT STEPS

1. ✅ **Deploy to AWS**: Follow steps above
2. ✅ **Test thoroughly**: All APIs working
3. ✅ **Connect Flutter**: Update IP and test
4. 📱 **Mobile testing**: Deploy to Android/iOS
5. 🔐 **Add security**: API keys, HTTPS
6. 📊 **Add monitoring**: CloudWatch alarms
7. 🚀 **Production**: Custom domain, CDN

---

## 📝 QUICK REFERENCE

```bash
# SSH to servers
ssh -i terraform-files/k3s-key ubuntu@<API_SERVER_IP>
ssh -i terraform-files/k3s-key ubuntu@<WORKER_SERVER_IP>

# Check services
kubectl get pods -A
kubectl logs -l app=availability
kubectl logs -l app=order
kubectl logs -l app=fulfillment

# View all AWS endpoints
cd terraform-files && terraform output

# Destroy everything (careful!)
terraform destroy -auto-approve
```

---

**🎉 YOU'RE READY TO DEPLOY TO AWS!**

Follow the steps above in order, and you'll have a fully functional AWS deployment with 2 EC2 instances running your Rapid Delivery Service.



Phase 4: CAP Theorem Testing
Test	What We Measure
Consistency	Manager updates stock → Buyer sees change immediately
Availability	Both apps work even during high load
Partition	What happens if Redis connection drops?


Now let me verify there are no missing files or errors by running Flutter analyze:

flutter analyze --no-fatal-infos