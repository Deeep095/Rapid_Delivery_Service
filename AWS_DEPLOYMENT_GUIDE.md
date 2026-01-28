# 🚀 AWS DEPLOYMENT - Step by Step Guide

## ✅ What's Fixed

### 1. Order History UI - WORKING! ✅
- Order service now properly stores orders in PostgreSQL
- Order history endpoint retrieves real orders from database
- Flutter app displays actual order history (not mock data)
- Fixed table schema with UUID order_id and timestamps

### 2. AWS Infrastructure Ready - 2 EC2 Instances ✅
- **API Server** (Instance 1): Availability + Order services
- **Worker Server** (Instance 2): Fulfillment worker
- All AWS resources (RDS, ElastiCache, OpenSearch, SQS) configured
- Still **FREE TIER** eligible

---

## 📋 DEPLOYMENT STEPS

### Prerequisites
- AWS CLI configured with credentials
- Terraform installed
- SSH key generated: `ssh-keygen -t rsa -b 4096 -f terraform-files/k3s-key`

---

### Step 1: Deploy Infrastructure (8-10 minutes)

**Option A: Automated Script (Recommended)**
```powershell
cd d:\Rapid_Delivery_Service
.\deploy_to_aws.ps1
```

**Option B: Manual**
```bash
cd terraform-files
terraform init
terraform plan
terraform apply -auto-approve
```

**What gets created:**
- ✅ 2 × EC2 t3.micro instances
- ✅ RDS PostgreSQL (publicly accessible)
- ✅ ElastiCache Redis (VPC-only)
- ✅ OpenSearch domain
- ✅ SQS queue
- ✅ Security groups & IAM roles

---

### Step 2: Save AWS Endpoints

```bash
cd terraform-files
terraform output > ../aws_endpoints.txt
```

**You'll need these values:**
```
api_server_ip      = "XX.XX.XX.XX"
worker_server_ip   = "YY.YY.YY.YY"
rds_endpoint       = "rapid-delivery-db.xxxxx.us-east-1.rds.amazonaws.com:5432"
opensearch_url     = "https://search-rapid-xxxxx.us-east-1.es.amazonaws.com"
sqs_queue_url      = "https://sqs.us-east-1.amazonaws.com/xxxxx/order-fulfillment-queue"
```

---

### Step 3: Wait for EC2 Initialization (5-7 minutes)

The instances are running startup scripts that:
1. Install k3s, Docker, AWS CLI
2. Configure kubectl
3. Pull Docker images from ECR
4. Deploy services to Kubernetes

**Your Flutter app is auto-configured!** 🎉  
The deployment script automatically runs `generate_flutter_config.ps1` which reads Terraform outputs and updates `rapid_delivery_app/lib/aws_config.dart`.

**Check progress:**
```bash
# SSH into API server
ssh -i terraform-files/k3s-key ubuntu@<API_SERVER_IP>

# View initialization log
sudo tail -f /var/log/cloud-init-output.log

# Check pods (should see 2 pods running)
kubectl get pods -A

# Expected output:
# availability-app-xxxxx   1/1   Running
# order-app-xxxxx          1/1   Running
```

**Check Worker server:**
```bash
ssh -i terraform-files/k3s-key ubuntu@<WORKER_SERVER_IP>

# Should see 1 pod
kubectl get pods -A

# Expected:
# fulfillment-worker-xxxxx  1/1  Running
```

---

### Step 4: Seed AWS Database

```bash
cd d:\Rapid_Delivery_Service
python seed_aws.py
```

**The script now auto-detects AWS endpoints from Terraform!** 🎉  
It will automatically read RDS and OpenSearch endpoints. If it can't detect them, it will prompt you.

**What gets seeded:**
- ✅ PostgreSQL: 16 inventory items across 2 warehouses
- ✅ OpenSearch: 3 warehouse locations with geo-coordinates
- ⚠️ Redis: Cannot seed from laptop (VPC-only), EC2 services will populate it

---

### Step 5: Test the APIs

Get your API server IP:
```bash
cd terraform-files
$API_IP = terraform output -raw api_server_ip
```

**Test Availability Service:**
```powershell
# Health check
curl http://${API_IP}:30001/

# Check stock near LNMIIT
curl "http://${API_IP}:30001/availability?item_id=apple&lat=26.94&lon=75.84"
```

Expected response:
```json
{
  "available": true,
  "warehouse_id": "wh_rajapark",
  "distance_km": 4.5,
  "quantity": 50
}
```

**Test Order Service:**
```powershell
# Health check
curl http://${API_IP}:30002/

# Place an order
curl -Method POST -Uri "http://${API_IP}:30002/orders" `
  -ContentType "application/json" `
  -Body '{"customer_id":"mobile_user","items":[{"item_id":"apple","warehouse_id":"wh_rajapark","quantity":2}]}'

# Get order history
curl http://${API_IP}:30002/orders/mobile_user
```

---

### Step 6: Update Flutter App

**Good news! Your Flutter app is already configured!** ✅

The `deploy_to_aws.ps1` script automatically generated `lib/aws_config.dart` with all AWS endpoints.

You just need to enable AWS mode:

Edit `rapid_delivery_app/lib/api_service.dart`:

```dart
// Line 16: Enable AWS mode
static const bool useAwsBackend = true;
```

**That's it!** No manual IP editing required. 🎉

---

### Step 7: Run Flutter App

```bash
cd rapid_delivery_app
flutter pub get
flutter run -d chrome
```

**Test Flow:**
1. ✅ Location picker shows → Select "📍 LNMIIT Campus"
2. ✅ Products show stock levels (green badges)
3. ✅ Add items to cart
4. ✅ Place order → Should succeed!
5. ✅ Navigate to "Orders" tab → See your order history with real data!

---

## 🏗️ ARCHITECTURE

```
┌─────────────────────────────────┐
│   FLUTTER APP (Your Laptop)    │
│   api_service.dart              │
└──────────────┬──────────────────┘
               │ HTTP
        ┌──────┴───────┐
        │              │
        ▼              ▼
┌────────────────┐  ┌────────────────┐
│ EC2 INSTANCE 1 │  │ EC2 INSTANCE 2 │
│  API SERVER    │  │ WORKER SERVER  │
│  t3.micro      │  │  t3.micro      │
├────────────────┤  ├────────────────┤
│ Availability   │  │ Fulfillment    │
│   :30001       │  │   Worker       │
│ Order          │  │                │
│   :30002       │  │                │
└────┬───────┬───┘  └────┬───────────┘
     │       │           │
     │       └───────────┼──────────┐
     │                   │          │
     ▼                   ▼          ▼
┌────────────┐     ┌──────────┐  ┌─────┐
│ OpenSearch │     │   RDS    │  │ SQS │
│ (geo-loc)  │     │(Postgres)│  │     │
└────────────┘     └────┬─────┘  └──┬──┘
                        │           │
                        │    ┌──────┘
     ┌──────────────────┴────┴──────┐
     │                               │
┌────┴────┐                  ┌───────┴──────┐
│  Redis  │                  │  Fulfillment │
│ (cache) │◄─────────────────┤    reads &   │
└─────────┘                  │  updates DB  │
                             └──────────────┘
```

---

## 📊 KEY AWS SERVICES

| Service | Port | Access | Purpose |
|---------|------|--------|---------|
| **RDS PostgreSQL** | 5432 | ✅ Public | Store orders & inventory |
| **OpenSearch** | 443 | ✅ Public | Geo-spatial warehouse search |
| **SQS** | - | ✅ Public (API) | Order processing queue |
| **ElastiCache Redis** | 6379 | ❌ VPC-only | Cache stock levels |
| **EC2 API Server** | 30001, 30002 | ✅ Public | HTTP APIs |
| **EC2 Worker** | - | ❌ Internal | Background processing |

**Note**: Redis is VPC-only by AWS design. Your EC2 services access it internally.

---

## 🐛 TROUBLESHOOTING

### Issue: EC2 pods not running

**Check logs:**
```bash
ssh -i terraform-files/k3s-key ubuntu@<IP>
sudo tail -100 /var/log/cloud-init-output.log
kubectl logs -l app=availability
```

**Common fixes:**
- Wait longer (initialization takes 5-7 mins)
- Check ECR image pull: `kubectl describe pod <pod-name>`
- Restart deployment: `kubectl rollout restart deployment/availability-app`

---

### Issue: Cannot connect to RDS

**Check security group:**
```bash
# RDS should allow traffic from EC2 security group
# Already configured with: self = true in databases.tf
```

**Test from laptop:**
```bash
# Install psql client
psql -h <RDS_ENDPOINT> -U postgres -d postgres
# Password: password123
```

---

### Issue: APIs return errors

**Check service health:**
```bash
curl http://<API_IP>:30001/
curl http://<API_IP>:30002/
```

**View pod logs:**
```bash
ssh ubuntu@<API_IP>
kubectl logs -l app=availability --tail=50
kubectl logs -l app=order --tail=50
```

---

### Issue: Out of memory on EC2

**Check memory:**
```bash
free -h
kubectl top nodes
kubectl top pods
```

**Solutions:**
- Already have 2GB swap enabled
- Already split across 2 instances
- If still issues, upgrade to t3.small:
  ```terraform
  instance_type = "t3.small"  # 2GB RAM
  ```

---

## 💰 COST BREAKDOWN

### Free Tier (12 months)
- 2 × EC2 t3.micro: **$0** (750 hrs each/month)
- RDS t3.micro: **$0** (750 hrs/month)
- ElastiCache t2.micro: **$0** (750 hrs/month)
- OpenSearch t3.small: **$0** (750 hrs/month)
- EBS 40GB: **~$1** (30GB free)
- **Total: ~$1/month**

### After Free Tier
- 2 × EC2: ~$15/mo
- RDS: ~$15/mo
- ElastiCache: ~$12/mo
- OpenSearch: ~$25/mo
- **Total: ~$67/month**

---

## 🔄 UPDATING SERVICES

### Update application code:
```bash
# Make changes to service code
cd availability-service

# Build and push to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ACCOUNT>.dkr.ecr.us-east-1.amazonaws.com

docker build -t availability:latest .
docker tag availability:latest <ECR_URL>:latest
docker push <ECR_URL>:latest

# Restart on EC2
ssh -i k3s-key ubuntu@<API_IP>
kubectl rollout restart deployment/availability-app
```

---

## 🧹 CLEANUP (Destroy Resources)

**To avoid charges after testing:**
```bash
cd terraform-files
terraform destroy -auto-approve
```

This will delete:
- All EC2 instances
- RDS database
- ElastiCache Redis
- OpenSearch domain
- SQS queue
- All associated resources

---

## ✅ CHECKLIST

- [ ] Terraform applied successfully
- [ ] EC2 instances running (2 instances)
- [ ] Pods running on both EC2 (3 total pods)
- [ ] AWS database seeded
- [ ] APIs responding on ports 30001 & 30002
- [ ] Flutter app updated with API server IP
- [ ] Order placement works
- [ ] Order history shows real data
- [ ] Location-based stock check works

---

## 🎉 SUCCESS CRITERIA

Your deployment is successful when:

1. ✅ `curl http://<API_IP>:30001/` returns healthy
2. ✅ Stock check returns available items for LNMIIT location
3. ✅ Order placement returns success with order_id
4. ✅ Order history shows placed orders
5. ✅ Flutter app connects and works end-to-end

**🎊 Congratulations! Your Rapid Delivery Service is live on AWS!**
