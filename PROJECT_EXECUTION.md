# 🚀 PROJECT EXECUTION GUIDE - Rapid Delivery Service

Complete step-by-step guide to deploy the Rapid Delivery Service from scratch.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud                                │
│                                                                  │
│  ┌─────────────────────┐      ┌─────────────────────┐           │
│  │   API Server (EC2)  │      │  Worker Server (EC2)│           │
│  │   t3.micro          │      │  t3.micro            │           │
│  │   ┌──────────────┐  │      │  ┌────────────────┐ │           │
│  │   │ Availability │  │      │  │ Fulfillment    │ │           │
│  │   │ :30001       │  │      │  │ Worker         │ │           │
│  │   └──────────────┘  │      │  └────────────────┘ │           │
│  │   ┌──────────────┐  │      │                      │           │
│  │   │ Order        │  │      │                      │           │
│  │   │ :30002       │  │      │                      │           │
│  │   └──────────────┘  │      │                      │           │
│  └───────────┬─────────┘      └──────────┬──────────┘           │
│              │                           │                       │
│              └───────────┬───────────────┘                       │
│                          │                                       │
│       ┌─────────┬────────┼────────┬─────────┐                   │
│       ▼         ▼        ▼        ▼         ▼                   │
│   ┌───────┐ ┌───────┐ ┌─────┐ ┌──────┐ ┌─────────┐             │
│   │  RDS  │ │ElastiC│ │ SQS │ │OpenS │ │   ECR   │             │
│   │Postgr │ │Redis  │ │     │ │earch │ │ Images  │             │
│   └───────┘ └───────┘ └─────┘ └──────┘ └─────────┘             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
           │
           │ HTTP
           ▼
    ┌──────────────┐
    │ Flutter App  │
    │ (Mobile/Web) │
    └──────────────┘
```

---

## PHASE 1: Prerequisites

### 1.1 Install Required Tools
```powershell
# Terraform
choco install terraform

# AWS CLI
choco install awscli

# Docker Desktop
# Download from https://docker.com

# Flutter
# Download from https://flutter.dev
flutter doctor

# Python (for seeding)
python --version  # Should be 3.8+
```

### 1.2 Configure AWS CLI
```powershell
aws configure
# Enter:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region: ap-south-1 (or your preferred)
# - Output format: json
```

### 1.3 Create ECR Repositories
```powershell
aws ecr create-repository --repository-name availability-service
aws ecr create-repository --repository-name order-service
aws ecr create-repository --repository-name fulfillment-worker
```

---

## PHASE 2: Build & Push Docker Images

### 2.1 Build Images Locally
```powershell
cd d:\Rapid_Delivery_Service

# Build all services
docker build -t availability-service:latest ./availability-service/
docker build -t order-service:latest ./order-service/
docker build -t fulfillment-worker:latest ./fulfillment-worker/
```

### 2.2 Push to ECR
```powershell
# Get ECR login
$ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
$REGION = "ap-south-1"

aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

# Tag and push each image
docker tag availability-service:latest "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/availability-service:latest"
docker tag order-service:latest "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/order-service:latest"
docker tag fulfillment-worker:latest "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/fulfillment-worker:latest"

docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/availability-service:latest"
docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/order-service:latest"
docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/fulfillment-worker:latest"
```

---

## PHASE 3: Deploy AWS Infrastructure

### 3.1 Generate SSH Key
```powershell
cd d:\Rapid_Delivery_Service\terraform-files
ssh-keygen -t rsa -b 4096 -f k3s-key -N ""
```

### 3.2 Initialize Terraform
```powershell
terraform init
```

### 3.3 Review Plan
```powershell
terraform plan
```

### 3.4 Apply Infrastructure
```powershell
terraform apply -auto-approve
```

**Wait 5-7 minutes** for EC2 user data scripts to complete.

### 3.5 Get Outputs
```powershell
terraform output

# Save these values:
# api_server_ip      = "x.x.x.x"
# worker_server_ip   = "x.x.x.x"
# rds_endpoint       = "xxx.rds.amazonaws.com:5432"
# redis_endpoint     = "xxx.cache.amazonaws.com:6379"
# opensearch_endpoint = "xxx.opensearch.amazonaws.com"
# sqs_queue_url      = "https://sqs..."
```

---

## PHASE 4: Seed Database

### 4.1 Install Python Dependencies
```powershell
pip install psycopg2-binary opensearch-py boto3
```

### 4.2 Update seed.py with AWS Endpoints

**Good news!** The `seed_aws.py` script now auto-detects AWS endpoints from Terraform!

If auto-detection fails, it will prompt you for:
- RDS Endpoint
- OpenSearch Endpoint

No need to manually edit the script. 🎉

### 4.3 Run Seeder
```powershell
python seed.py
```

Expected output:
```
✓ Connected to PostgreSQL
✓ Created inventory table
✓ Seeded 10 products
✓ Created orders table
✓ Connected to OpenSearch
✓ Created warehouses index
✓ Seeded 3 warehouses (Jaipur area)
```

---

## PHASE 5: Verify EC2 Services

### 5.1 SSH into API Server
```powershell
ssh -i terraform-files/k3s-key ubuntu@<API_SERVER_IP>
```

### 5.2 Check Pods
```bash
kubectl get pods -A

# Expected:
# default   availability-app-xxx   1/1   Running
# default   order-app-xxx          1/1   Running
```

### 5.3 Check ConfigMap
```bash
sudo k3s kubectl get configmap service-config -o yaml

# If you want to use plain `kubectl` without sudo (optional):
# mkdir -p ~/.kube
# sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
# sudo chown $USER:$USER ~/.kube/config

# Should show all AWS endpoints:
# POSTGRES_HOST, REDIS_HOST, OPENSEARCH_HOST, SQS_QUEUE_URL
```

### 5.4 Test from EC2
```bash
# Availability
curl http://localhost:30001/

# Order
curl http://localhost:30002/
```

### 5.5 Check Worker Server
```powershell
ssh -i terraform-files/k3s-key ubuntu@<WORKER_SERVER_IP>
```

```bash
kubectl get pods -A

# Expected:
# default   fulfillment-worker-xxx   1/1   Running
```

---

## PHASE 6: Configure Flutter App

### 6.1 Automatic Configuration ✅

**Good news!** If you used `deploy_to_aws.ps1`, your Flutter app is already configured!

The deployment script automatically runs `generate_flutter_config.ps1` which:
- Reads all Terraform outputs
- Generates `rapid_delivery_app/lib/aws_config.dart` with all AWS endpoints
- No manual editing required!

To verify, check [aws_config.dart](rapid_delivery_app/lib/aws_config.dart) - you should see your actual AWS IPs and endpoints.

### 6.2 Manual Configuration (if needed)

If you deployed with `terraform apply` directly (not the script), run:

```powershell
cd d:\Rapid_Delivery_Service
.\generate_flutter_config.ps1
```

This will read Terraform outputs and update the Flutter config automatically.

### 6.3 Enable AWS Backend

Edit `rapid_delivery_app/lib/api_service.dart`:

```dart
// Change this to true for AWS
static const bool useAwsBackend = true;
```

That's it! The API URLs are automatically read from `aws_config.dart`.

### 6.4 Run Flutter App
```powershell
cd rapid_delivery_app
flutter pub get
flutter run -d chrome --web-browser-flag "--disable-web-security"
```

---

## PHASE 7: End-to-End Test

### 7.1 Test Flow
1. **Open app** in browser
2. **Select location** → Choose "📍 LNMIIT Campus" or "📍 Jagatpura"
3. **Browse products** → Should see apples, bananas, etc. with stock levels
4. **Add to cart** → Add 2-3 items
5. **Checkout** → Place order
6. **Orders tab** → Verify order appears in history

### 7.2 Verify Database
```powershell
# Check order was stored in RDS
$RDS = "your-rds-endpoint.rds.amazonaws.com"
psql -h $RDS -U postgres -c "SELECT * FROM orders ORDER BY created_at DESC LIMIT 5;"
```

---

## PHASE 8: Cleanup (When Done)

### 8.1 Destroy AWS Resources
```powershell
cd terraform-files
terraform destroy -auto-approve
```

### 8.2 Delete ECR Images
```powershell
aws ecr delete-repository --repository-name availability-service --force
aws ecr delete-repository --repository-name order-service --force
aws ecr delete-repository --repository-name fulfillment-worker --force
```

---

## Quick Reference

### Important Files
| File | Purpose |
|------|---------|
| `terraform-files/compute.tf` | EC2 instances (api_server, worker_server) |
| `terraform-files/user_data_api.sh` | API server k3s setup |
| `terraform-files/user_data_worker.sh` | Worker server k3s setup |
| `terraform-files/outputs.tf` | All AWS endpoints |
| `seed.py` | Database seeding script |
| `rapid_delivery_app/lib/aws_config.dart` | Flutter AWS configuration |
| `rapid_delivery_app/lib/api_service.dart` | API client (AWS/Local toggle) |

### Ports
| Service | Local | AWS |
|---------|-------|-----|
| Availability | 8000 | 30001 |
| Order | 8001 | 30002 |
| PostgreSQL | 5432 | 5432 |
| Redis | 6379 | 6379 |
| OpenSearch | 9200 | 443 |

### Common Issues

| Issue | Solution |
|-------|----------|
| EC2 pods not running | Wait 5-7 min, check with `kubectl get pods -A` |
| Can't connect to Redis from laptop | **Expected** - ElastiCache is VPC-only |
| No stock found | Run `python seed.py` to seed warehouses |
| Order history empty | Place an order first, then check history |
| Security group blocking | Check port 30001, 30002 in AWS console |

---

## Cost Estimate (AWS Free Tier)

| Resource | Free Tier | Monthly Cost |
|----------|-----------|--------------|
| 2x t3.micro EC2 | 750 hrs/mo | $0* |
| RDS db.t3.micro | 750 hrs/mo | $0* |
| ElastiCache t3.micro | 750 hrs/mo | $0* |
| OpenSearch t3.small | 750 hrs/mo | $0* |
| SQS | 1M requests | $0* |

*Within free tier limits for first 12 months

---

## 🖥️ Local Development Setup

For local development without AWS, use the `local/` folder setup.

### Quick Start - Local
```powershell
# 1. Start Docker services
cd d:\Rapid_Delivery_Service\local
docker-compose -f docker-compose-local.yaml up -d

# 2. Wait for services (~30 seconds)
docker ps

# 3. Seed databases
python seed_local.py

# 4. Update Flutter config
# In rapid_delivery_app/lib/api_service.dart:
# Set: useAwsBackend = false

# 5. Run Flutter app
cd ..\rapid_delivery_app
flutter run -d chrome
```

### Local Services
| Service | URL |
|---------|-----|
| PostgreSQL | localhost:5432 |
| Redis | localhost:6379 |
| OpenSearch | localhost:9200 |

### Test Coordinates for Local
| City | Lat | Lon |
|------|-----|-----|
| Jaipur | 26.9124 | 75.7873 |
| Delhi | 28.6139 | 77.2090 |
| Mumbai | 19.0760 | 72.8777 |

### Stop Local Services
```powershell
cd local
docker-compose -f docker-compose-local.yaml down
```

---

## 📱 Flutter App Structure

```
rapid_delivery_app/lib/
├── main.dart                  # App entry point
├── models.dart                # Data models (Product, Category, etc.)
├── api_service.dart           # API client (AWS/Local toggle)
├── aws_config.dart            # Auto-generated AWS endpoints
├── data_repository.dart       # Product catalog & banners
├── home_screen.dart           # Legacy home screen
├── location_sheet.dart        # Location picker
├── orders_screen.dart         # Order list (legacy)
├── widgets/                   # Reusable UI components
│   ├── widgets.dart           # Barrel export
│   ├── banner_carousel.dart   # Promo banners
│   ├── category_chips.dart    # Category filter
│   ├── product_card.dart      # Product display card
│   ├── cart_bottom_bar.dart   # Sticky cart bar
│   └── delivery_address_bar.dart
├── screens/
│   ├── role_selection_screen.dart  # Login/role picker
│   ├── buyer/
│   │   ├── buyer_home_screen.dart  # Main shopping screen
│   │   ├── cart_screen.dart        # Cart & checkout
│   │   └── order_history_screen.dart
│   └── manager/
│       ├── manager_home_screen.dart  # Warehouse selector
│       └── inventory_screen.dart     # Stock management
└── services/
    ├── auth_service.dart      # Google/demo auth
    └── inventory_service.dart # Manager API calls
```

