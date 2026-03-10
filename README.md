# 🚀 Rapid Delivery Service

A **cloud-native microservices platform** that enables real-time product availability lookup, order placement, and asynchronous order fulfillment for a rapid delivery application.

The project demonstrates a **modern distributed system architecture** using:

* **FastAPI microservices**
* **Flutter frontend**
* **Redis caching**
* **OpenSearch geo-location queries**
* **PostgreSQL transactions**
* **AWS cloud infrastructure**
* **Terraform infrastructure-as-code**
* **Kubernetes (k3s) container orchestration**

The architecture simulates the backend design used by **quick-commerce platforms such as Blinkit, Zepto, and Instamart**.

---

# 🏗 Architecture Overview

The system follows a **microservices architecture**, where each service is responsible for a specific domain.

```
Flutter App (Web / Mobile)
        │
        ▼
      NGINX
        │
 ┌───────────────┬───────────────┐
 ▼               ▼               ▼
Availability   Order        Fulfillment
Service        Service       Worker
```

### Services

| Service              | Port       | Purpose                                 |
| -------------------- | ---------- | --------------------------------------- |
| Availability Service | 8000       | Product availability & warehouse search |
| Order Service        | 8001       | Order placement and order history       |
| Fulfillment Worker   | background | Processes orders asynchronously         |

Each service interacts with data stores optimized for its workload.

---

# 🧠 System Design

## Availability Service

Handles read-heavy workloads such as:

* product availability lookup
* warehouse search by location
* inventory management

Uses:

* **Redis** → fast stock lookup
* **OpenSearch** → geo queries

---

## Order Service

Handles transactional operations such as:

* placing orders
* storing order history
* sending events to queue

Uses:

* **PostgreSQL**

---

## Fulfillment Worker

A background job processor that:

* polls **AWS SQS**
* processes pending orders
* updates Redis stock
* marks orders as completed

---

# 🔄 Order Processing Flow

```
User places order
        │
        ▼
Order Service saves order (Postgres)
        │
        ▼
Message sent to SQS queue
        │
        ▼
Fulfillment Worker processes order
        │
        ├── update Redis inventory
        └── update order status
```

This design enables **asynchronous processing and scalability**.

---

# ☁️ AWS Infrastructure

The system can be deployed on AWS using **Terraform**.

Infrastructure components include:

| Component         | Purpose                        |
| ----------------- | ------------------------------ |
| EC2               | Runs microservices             |
| k3s               | Lightweight Kubernetes cluster |
| RDS PostgreSQL    | Order database                 |
| ElastiCache Redis | Inventory cache                |
| OpenSearch        | Geo search for warehouses      |
| SQS               | Order processing queue         |
| ECR               | Container image registry       |

Example deployment:

```
EC2 API Server
   ├─ Availability Service
   └─ Order Service

EC2 Worker Server
   └─ Fulfillment Worker

Shared Services
   ├─ Redis
   ├─ PostgreSQL
   ├─ OpenSearch
   └─ SQS
```

---

# 🐳 Local Development

Run the system locally using **Docker Compose**.

Start services:

```
cd local
docker-compose -f docker-compose-local.yaml up -d --build
```

Seed local data:

```
python seed_local.py
```

Run Flutter frontend:

```
cd rapid_delivery_app
flutter run -d chrome --web-browser-flag "--disable-web-security"
```

Verify services:

```
curl http://localhost:8000/
curl http://localhost:8001/
```

---

# ☁️ Deploy to AWS

Infrastructure is created using **Terraform**.

```
cd terraform-files
terraform init
terraform apply
```

Resources created include:

* EC2 API server
* EC2 worker server
* RDS PostgreSQL
* ElastiCache Redis
* OpenSearch cluster
* SQS queue

Verify deployment:

```
terraform output
```

---

# 🧪 Testing

API endpoints can be tested using `curl`.

### Availability API

Health check:

```
curl http://localhost:8000/
```

Stock availability query:

```
curl "http://localhost:8000/availability?item_id=apple&lat=26.9&lon=75.8"
```

---

### Order API

Place an order:

```
curl -X POST http://localhost:8001/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"test_user","items":[{"item_id":"apple","warehouse_id":"wh_lnmiit","quantity":2}]}'
```

Get order history:

```
curl http://localhost:8001/orders/test_user
```

---

# ⚡ Performance Benchmarks

Local benchmark results:

| Endpoint         | Requests/sec |
| ---------------- | ------------ |
| Availability API | ~106 req/s   |
| Product lookup   | ~100 req/s   |
| Order creation   | ~17 req/s    |

Estimated AWS capacity:

| Instance  | Estimated Users |
| --------- | --------------- |
| t3.micro  | ~20 users       |
| t3.small  | ~50 users       |
| t3.medium | ~80 users       |

The architecture supports **horizontal scaling using load balancers or Kubernetes autoscaling**.

---

# 📱 Flutter Application

The Flutter client supports two roles.

## Buyer

* browse products
* check stock availability
* add items to cart
* place orders
* view order history

## Warehouse Manager

* manage inventory
* update stock levels
* view warehouse dashboard

---

# 🔮 Future Improvements

Planned enhancements include:

* Push notifications
* Payment gateway integration
* Live order tracking
* Multiple delivery addresses
* Promo code support
* API Gateway integration
* Service mesh (Istio / Linkerd)
* Event-driven architecture using EventBridge
* Multi-region deployment

---

# 📁 Project Structure

```
Rapid_Delivery_Service
│
├── availability-service
├── order-service
├── fulfillment-worker
│
├── terraform-files
│
├── rapid_delivery_app
│
├── local
│
├── seed scripts
│
└── documentation
```

---

# 🧹 Cleanup

Destroy AWS infrastructure when finished:

```
terraform destroy
```

---

# 📌 Key Concepts Demonstrated

* Microservices architecture
* Infrastructure as Code (Terraform)
* Containerization with Docker
* Kubernetes orchestration (k3s)
* Asynchronous messaging with SQS
* Distributed caching using Redis
* Geo-location search using OpenSearch
* Cloud-native application design

---

# ⭐ Contributing

Contributions are welcome.
Feel free to open issues or submit pull requests.

---

