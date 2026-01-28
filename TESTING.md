# 🧪 TESTING GUIDE - Rapid Delivery Service

## Quick Reference

| Environment | Availability API | Order API |
|-------------|-----------------|-----------|
| **Local** | http://localhost:8000 | http://localhost:8001 |
| **AWS** | http://[EC2_IP]:30001 | http://[EC2_IP]:30002 |

---

## 1️⃣ LOCAL TESTING (Docker)

### Start Services
```powershell
cd d:\Rapid_Delivery_Service
docker-compose up -d
```

### Seed Database
```powershell
python seed.py
```

### Verify Services Running
```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Expected output:
```
NAMES                  STATUS          PORTS
availability-service   Up X minutes    0.0.0.0:8000->8000/tcp
order-service          Up X minutes    0.0.0.0:8001->8001/tcp
fulfillment-worker     Up X minutes
postgres               Up X minutes    0.0.0.0:5432->5432/tcp
redis                  Up X minutes    0.0.0.0:6379->6379/tcp
opensearch             Up X minutes    0.0.0.0:9200->9200/tcp
```

### API Tests

**Test 1: Availability Health Check**
```powershell
curl http://localhost:8000/
# Expected: {"status":"healthy","service":"availability-service"}
```

**Test 2: Stock Check (Near LNMIIT - should find stock)**
```powershell
curl "http://localhost:8000/availability?item_id=apple&lat=26.94&lon=75.84"
# Expected: {"available":true,"warehouse_id":"wh_rajapark","distance_km":4.5,"quantity":50}
```

**Test 3: Stock Check (Far location - no delivery)**
```powershell
curl "http://localhost:8000/availability?item_id=apple&lat=26.45&lon=74.64"
# Expected: {"available":false,"message":"No stock or no delivery in your area"}
```

**Test 4: Order Health Check**
```powershell
curl http://localhost:8001/
# Expected: {"status":"healthy","service":"order-service"}
```

**Test 5: Place Order**
```powershell
curl -Method POST -Uri "http://localhost:8001/orders" `
  -ContentType "application/json" `
  -Body '{"customer_id":"test_user","items":[{"item_id":"apple","warehouse_id":"wh_rajapark","quantity":2}]}'
# Expected: {"status":"success","order_id":"<uuid>","message":"Order placed successfully"}
```

**Test 6: Get Order History**
```powershell
curl http://localhost:8001/orders/test_user
# Expected: Array of orders with order_id, customer_id, status, items, created_at
```

### Flutter App Test
```powershell
cd rapid_delivery_app
flutter run -d chrome
```

**Test Flow:**
1. ✅ Location picker opens → Select "📍 LNMIIT Campus"
2. ✅ Products show stock levels (green/red badges)
3. ✅ Add items to cart
4. ✅ Place order → Should succeed
5. ✅ Check Orders tab → See real order history

### Stop Local Services
```powershell
docker-compose down
```

---

## 2️⃣ AWS TESTING

### Prerequisites
- Terraform applied successfully
- EC2 instances initialized (wait 5-7 min after terraform apply)

### Get AWS Endpoints
```powershell
cd terraform-files
terraform output
```

### SSH into EC2 Instances
```powershell
# API Server
ssh -i k3s-key ubuntu@<API_SERVER_IP>

# Worker Server
ssh -i k3s-key ubuntu@<WORKER_SERVER_IP>
```

### Check Pods on EC2
```bash
# On API Server - should see 2 pods
kubectl get pods -A

# Expected:
# NAMESPACE   NAME                              READY   STATUS    
# default     availability-app-xxxxx            1/1     Running   
# default     order-app-xxxxx                   1/1     Running   

# On Worker Server - should see 1 pod
kubectl get pods -A

# Expected:
# NAMESPACE   NAME                              READY   STATUS    
# default     fulfillment-worker-xxxxx          1/1     Running   
```

### API Tests (from your laptop)
```powershell
$API_IP = "YOUR_API_SERVER_IP"

# Availability health
curl http://${API_IP}:30001/

# Stock check
curl "http://${API_IP}:30001/availability?item_id=apple&lat=26.94&lon=75.84"

# Order health
curl http://${API_IP}:30002/

# Place order
curl -Method POST -Uri "http://${API_IP}:30002/orders" `
  -ContentType "application/json" `
  -Body '{"customer_id":"mobile_user","items":[{"item_id":"apple","warehouse_id":"wh_rajapark","quantity":2}]}'

# Get orders
curl http://${API_IP}:30002/orders/mobile_user
```

### Flutter App Test with AWS
1. Edit `lib/aws_config.dart`:
   ```dart
   static const String apiServerIp = "YOUR_API_SERVER_IP";
   ```

2. Edit `lib/api_service.dart`:
   ```dart
   static const bool useAwsBackend = true;
   ```

3. Run app:
   ```powershell
   cd rapid_delivery_app
   flutter run -d chrome
   ```

---

## 3️⃣ DATABASE VERIFICATION

### Local PostgreSQL
```powershell
docker exec postgres psql -U postgres -c "SELECT * FROM orders LIMIT 5;"
docker exec postgres psql -U postgres -c "SELECT * FROM inventory LIMIT 10;"
```

### AWS RDS (from laptop)
```powershell
# Install psql if needed, then:
psql -h <RDS_ENDPOINT> -U postgres -d postgres -c "SELECT * FROM orders LIMIT 5;"
# Password: password123
```

### Check Warehouses in OpenSearch
```powershell
# Local
curl http://localhost:9200/warehouses/_search?pretty

# AWS (from EC2)
curl https://<OPENSEARCH_ENDPOINT>/warehouses/_search?pretty
```

---

## 4️⃣ TROUBLESHOOTING

### Issue: "Connection refused" locally
```powershell
# Check if containers are running
docker ps

# Restart if needed
docker-compose down
docker-compose up -d
```

### Issue: "No delivery available" everywhere
```powershell
# Re-seed the database
python seed.py

# Verify warehouses exist
curl http://localhost:9200/warehouses/_search?pretty
```

### Issue: AWS pods not running
```bash
# SSH into EC2
ssh -i k3s-key ubuntu@<IP>

# Check pod status
kubectl get pods -A

# View pod logs
kubectl logs -l app=availability --tail=50
kubectl logs -l app=order --tail=50

# Describe pod for errors
kubectl describe pod <pod-name>
```

### Issue: Order placement fails
```powershell
# Check order service logs
docker logs order-service --tail=30

# Verify database schema
docker exec postgres psql -U postgres -c "\d orders"
```

---

## 5️⃣ EXPECTED TEST RESULTS

| Test | Local Expected | AWS Expected |
|------|---------------|--------------|
| Availability health | ✅ healthy | ✅ healthy |
| Stock near LNMIIT | ✅ available, ~50 qty | ✅ available, ~50 qty |
| Stock far away | ❌ not available | ❌ not available |
| Order health | ✅ healthy | ✅ healthy |
| Place order | ✅ success + order_id | ✅ success + order_id |
| Order history | ✅ returns orders | ✅ returns orders |
| Flutter cart | ✅ works | ✅ works |
| Flutter checkout | ✅ works | ✅ works |
