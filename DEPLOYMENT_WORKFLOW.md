# 🚀 Rapid Delivery Service - Deployment & Update Workflow

## 📋 Table of Contents
1. [Fresh Deployment (terraform apply)](#fresh-deployment)
2. [Service Update Workflow](#service-update-workflow)
3. [Quick Reference Commands](#quick-reference-commands)

---

## 🆕 Fresh Deployment (terraform apply)

### Pre-requisites
```powershell
# 1. Ensure you're in terraform-files directory
cd d:\Rapid_Delivery_Service\terraform-files

# 2. Verify AWS credentials are configured
aws sts get-caller-identity
```

### Step 1: Deploy Infrastructure
```powershell
terraform init
terraform apply --auto-approve
```

This creates:
- ✅ VPC, Security Groups
- ✅ RDS PostgreSQL
- ✅ ElastiCache Redis
- ✅ OpenSearch
- ✅ SQS Queue
- ✅ ECR Repositories
- ✅ 2 EC2 Instances (K3s Master + Worker)

**Wait ~5-7 minutes** for EC2 instances to initialize.

### Step 2: Update Flutter Config
```powershell
cd terraform-files
./generate_flutter_config.ps1
```
This updates `rapid_delivery_app/lib/aws_config.dart` with new IPs.

### Step 3: Seed Data (Required!)

#### 3a. Seed RDS Database (from laptop)
```powershell
cd d:\Rapid_Delivery_Service
python seed_aws.py
```

#### 3b. Seed OpenSearch & Redis (from EC2)
Redis is VPC-only, so you must SSH into EC2:
```powershell
# Get the master IP from terraform output
$masterIp = (terraform output -json | ConvertFrom-Json).api_server_ip.value

# SSH into master
ssh -i "terraform-files/k3s-key" ubuntu@$masterIp
```

Then on EC2:
```bash
# Install required packages
pip3 install boto3 requests-aws4auth redis

# Copy and run the warehouse seeder
python3 << 'SEED_SCRIPT'
import redis
import requests
import boto3
from requests_aws4auth import AWS4Auth

# Config
REDIS_HOST = "rapid-redis.pqqgpc.0001.use1.cache.amazonaws.com"
OPENSEARCH_URL = "https://search-rapid-search-bu2kcyndpnpudetiv3s6raq5oa.us-east-1.es.amazonaws.com"
AWS_REGION = "us-east-1"

# Get AWS auth
credentials = boto3.Session().get_credentials()
auth = AWS4Auth(credentials.access_key, credentials.secret_key, AWS_REGION, 'es', session_token=credentials.token)

# Connect to Redis
r = redis.Redis(host=REDIS_HOST, port=6379)

# Warehouses with locations
warehouses = [
    {"id": "wh_jaipur_central", "lat": 26.9124, "lon": 75.7873, "city": "Jaipur Central"},
    {"id": "wh_jaipur_amer", "lat": 26.9855, "lon": 75.8513, "city": "Jaipur Amer"},
    {"id": "wh_jaipur_malviya", "lat": 26.8505, "lon": 75.8043, "city": "Jaipur Malviya Nagar"},
    {"id": "wh_lnmiit", "lat": 26.9020, "lon": 75.8680, "city": "LNMIIT Jaipur"},
    {"id": "wh_delhi_central", "lat": 28.6139, "lon": 77.2090, "city": "Delhi Central"},
    {"id": "wh_delhi_gurgaon", "lat": 28.4595, "lon": 77.0266, "city": "Gurgaon"},
    {"id": "wh_delhi_noida", "lat": 28.5355, "lon": 77.3910, "city": "Noida"},
    {"id": "wh_mumbai_central", "lat": 19.0760, "lon": 72.8777, "city": "Mumbai Central"},
    {"id": "wh_mumbai_thane", "lat": 19.2183, "lon": 72.9781, "city": "Thane"},
    {"id": "wh_bangalore_central", "lat": 12.9716, "lon": 77.5946, "city": "Bangalore Central"},
    {"id": "wh_chennai_central", "lat": 13.0827, "lon": 80.2707, "city": "Chennai Central"},
]

# Products
products = ["apple", "milk", "bread", "coke", "chips", "eggs", "banana", "cookie", "water", "rice"]

# Create OpenSearch index
try:
    requests.delete(f"{OPENSEARCH_URL}/warehouses", auth=auth, timeout=10)
except: pass

mapping = {"mappings": {"properties": {"id": {"type": "keyword"}, "location": {"type": "geo_point"}, "city": {"type": "text"}}}}
requests.put(f"{OPENSEARCH_URL}/warehouses", json=mapping, auth=auth, timeout=10)

# Seed each warehouse
for wh in warehouses:
    # Add to OpenSearch
    doc = {"id": wh["id"], "location": {"lat": wh["lat"], "lon": wh["lon"]}, "city": wh["city"]}
    requests.put(f"{OPENSEARCH_URL}/warehouses/_doc/{wh['id']}", json=doc, auth=auth, timeout=10)
    
    # Add inventory to Redis
    for product in products:
        r.set(f"{wh['id']}:{product}", 100)
    print(f"✅ Added {wh['id']}")

print(f"\n🎉 Seeded {len(warehouses)} warehouses with {len(products)} products each!")
SEED_SCRIPT
```

### Step 4: Verify Deployment
```bash
# On EC2
kubectl get pods
kubectl get svc
curl http://localhost/availability/availability?item_id=apple&lat=26.85&lon=75.80
```

### Step 5: Run Flutter App
```powershell
cd d:\Rapid_Delivery_Service\rapid_delivery_app
flutter run -d chrome
```

---

## 🔄 Service Update Workflow

When you modify a service's Python code (e.g., `availability-service/main.py`):

### Step 1: Update Code Locally
Edit the files in your service folder:
- `availability-service/main.py`
- `availability-service/requirements.txt`
- etc.

### Step 2: Build New Docker Image
```powershell
cd d:\Rapid_Delivery_Service\availability-service
docker build -t availability-service:v2 .
```

### Step 3: Tag for ECR
```powershell
# Get ECR URI
$ecrUri = "905418449359.dkr.ecr.us-east-1.amazonaws.com"

# Tag with new version AND latest
docker tag availability-service:v2 $ecrUri/availability-service:v2
docker tag availability-service:v2 $ecrUri/availability-service:latest
```

### Step 4: Login to ECR
```powershell
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ecrUri
```

### Step 5: Push to ECR
```powershell
docker push $ecrUri/availability-service:v2
docker push $ecrUri/availability-service:latest
```

### Step 6: Update K8s Deployment (SSH into EC2)
```bash
# Option A: Force pull latest image
kubectl rollout restart deployment/availability-app

# Option B: Update to specific version
kubectl set image deployment/availability-app availability=$ecrUri/availability-service:v2

# Check rollout status
kubectl rollout status deployment/availability-app
```

### Step 7: Verify
```bash
kubectl get pods
kubectl logs -l app=availability --tail=20
curl http://localhost:30001/
```

---

## 📝 Quick Reference Commands

### SSH into EC2
```powershell
ssh -i "d:\Rapid_Delivery_Service\terraform-files\k3s-key" ubuntu@54.144.200.236
```

### Check All Services
```bash
kubectl get pods -o wide
kubectl get svc
kubectl logs <pod-name> --tail=50
```

### Test APIs
```bash
# Availability
curl "http://localhost/availability/availability?item_id=apple&lat=26.85&lon=75.80"

# Order
curl -X POST "http://localhost/order/orders" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"test1","items":[{"item_id":"apple","warehouse_id":"wh_jaipur_malviya","quantity":1}]}'

# Health
curl http://localhost/health
```

### Restart a Service
```bash
kubectl rollout restart deployment/availability-app
kubectl rollout restart deployment/order-app
kubectl rollout restart deployment/fulfillment-worker
```

### View Logs
```bash
kubectl logs -l app=availability --tail=100 -f
kubectl logs -l app=order --tail=100 -f
```

### Check Redis
```bash
redis-cli -h rapid-redis.pqqgpc.0001.use1.cache.amazonaws.com keys "*" | head -20
```

### Check OpenSearch
```bash
curl -s "https://search-rapid-search-bu2kcyndpnpudetiv3s6raq5oa.us-east-1.es.amazonaws.com/warehouses/_search?size=5" \
  --aws-sigv4 "aws:amz:us-east-1:es" \
  --user "$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/rapid_delivery_ec2_role | jq -r '.AccessKeyId'):$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/rapid_delivery_ec2_role | jq -r '.SecretAccessKey')" \
  -H "x-amz-security-token: $(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/rapid_delivery_ec2_role | jq -r '.Token')"
```

---

## 🏗️ Service Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     FLUTTER APP (Web/Mobile)                     │
└─────────────────────────────────┬───────────────────────────────┘
                                  │ HTTP
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    EC2 MASTER (54.144.200.236)                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                    NGINX (Port 80)                          ││
│  │   /availability/* → :30001    /order/* → :30002             ││
│  └─────────────────────────────────────────────────────────────┘│
│  ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐│
│  │ availability-app │ │    order-app     │ │fulfillment-worker││
│  │    (NodePort     │ │    (NodePort     │ │   (ClusterIP)    ││
│  │      30001)      │ │      30002)      │ │                  ││
│  └────────┬─────────┘ └────────┬─────────┘ └────────┬─────────┘│
└───────────┼────────────────────┼────────────────────┼───────────┘
            │                    │                    │
            ▼                    ▼                    ▼
    ┌───────────────┐    ┌───────────────┐    ┌───────────────┐
    │  OpenSearch   │    │  PostgreSQL   │    │   SQS Queue   │
    │  (Warehouses) │    │   (Orders)    │    │(Order Events) │
    └───────────────┘    └───────────────┘    └───────────────┘
            │
            ▼
    ┌───────────────┐
    │    Redis      │
    │  (Inventory)  │
    └───────────────┘
```

---

## ⚠️ Important Notes

1. **Redis is VPC-only**: You cannot connect to ElastiCache from your laptop. Always SSH to EC2.

2. **OpenSearch requires IAM auth**: The availability service uses boto3 for SigV4 signing.

3. **After terraform destroy/apply**: 
   - IPs change → Run `./generate_flutter_config.ps1`
   - Data is lost → Re-run seed scripts

4. **Flutter Web CORS**: The Nginx config includes CORS headers. If issues persist, run with:
   ```powershell
   flutter run -d chrome --web-browser-flag "--disable-web-security"
   ```

5. **ECR Image Updates**: K8s uses `imagePullPolicy: Always` by default with `:latest` tag, so `kubectl rollout restart` will pull the newest image.
