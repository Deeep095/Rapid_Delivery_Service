# Future Works - Rapid Delivery Service Architecture

## Current Architecture: How Services Work Together

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           FLUTTER APP (Buyer/Manager)                            │
│                    Runs on Web Browser / Android / iOS                           │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                          HTTP REST API calls
                                        │
                    ┌───────────────────┴───────────────────┐
                    ▼                                       ▼
┌─────────────────────────────────┐       ┌─────────────────────────────────┐
│     AVAILABILITY SERVICE        │       │       ORDER SERVICE             │
│     (FastAPI - Port 8000)       │       │     (FastAPI - Port 8001)       │
│                                 │       │                                 │
│  • Check product availability   │       │  • Place orders                 │
│  • Find nearest warehouse       │       │  • Order history                │
│  • Manage inventory (CRUD)      │       │  • Send to SQS queue            │
│  • Return products with stock   │       │                                 │
└───────────────┬─────────────────┘       └───────────────┬─────────────────┘
                │                                         │
        ┌───────┴───────┐                         ┌───────┴───────┐
        ▼               ▼                         ▼               ▼
┌───────────────┐ ┌───────────────┐       ┌───────────────┐ ┌───────────────┐
│     REDIS     │ │  OPENSEARCH   │       │   POSTGRES    │ │   AWS SQS     │
│   (Cache)     │ │  (Geo Search) │       │  (Database)   │ │   (Queue)     │
│               │ │               │       │               │ │               │
│ • Stock levels│ │ • Warehouse   │       │ • Orders      │ │ • Order msgs  │
│ • Fast reads  │ │   locations   │       │ • Customers   │ │ • Async jobs  │
│ • Key-value   │ │ • Geo queries │       │ • History     │ │               │
└───────────────┘ └───────────────┘       └───────────────┘ └───────┬───────┘
                                                                    │
                                                                    ▼
                                          ┌─────────────────────────────────┐
                                          │      FULFILLMENT WORKER         │
                                          │        (Background Job)         │
                                          │                                 │
                                          │  • Polls SQS queue              │
                                          │  • Processes orders             │
                                          │  • Updates stock in Redis       │
                                          │  • Updates order status in DB   │
                                          └─────────────────────────────────┘
```

---

## Why Microservices Instead of Monolith?

### 1. **Independent Scaling**
Each service can scale independently based on load:
- Black Friday sale? Scale up Order Service
- Lot of searches? Scale up Availability Service
- Normal day? Keep minimal instances

### 2. **Technology Freedom**
- Each service can use the best tool for its job
- Availability: Redis (fast cache) + OpenSearch (geo queries)
- Orders: PostgreSQL (ACID transactions)

### 3. **Fault Isolation**
- If Order Service crashes, users can still browse products
- If Availability crashes, existing orders still process

### 4. **Team Independence**
- Team A works on inventory features
- Team B works on order processing
- No code conflicts!

### 5. **Deployment Flexibility**
- Deploy Order Service without touching Availability
- Rollback one service without affecting others

---

## Data Flow Example: Placing an Order

```
1. User clicks "Place Order" in Flutter app
                    │
                    ▼
2. POST /orders → Order Service
                    │
   ┌────────────────┼────────────────┐
   │                │                │
   ▼                ▼                ▼
3. Save to    4. Send to      5. Return 
   Postgres      SQS Queue       order_id
   (PENDING)                     to user
                    │
                    ▼
6. Fulfillment Worker picks up message
                    │
   ┌────────────────┼────────────────┐
   │                │                │
   ▼                ▼                ▼
7. Deduct      8. Update       9. Delete
   stock from     order to        message
   Redis          COMPLETED       from SQS
```

---

## YES! You Can Deploy on EC2 and Scale

### How to Scale Using EC2 Instances

You're absolutely correct! Here's how to deploy and scale:

### Option 1: Multiple EC2 Instances + Load Balancer (Recommended for Starting)

```
                    ┌─────────────────────────────────┐
                    │     Application Load Balancer   │
                    │         (AWS ALB)               │
                    │                                 │
                    │  • Routes traffic               │
                    │  • Health checks                │
                    │  • SSL termination              │
                    └───────────────┬─────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
              ▼                     ▼                     ▼
┌─────────────────────┐ ┌─────────────────────┐ ┌─────────────────────┐
│     EC2 Instance 1  │ │     EC2 Instance 2  │ │     EC2 Instance 3  │
│                     │ │                     │ │                     │
│  ┌───────────────┐  │ │  ┌───────────────┐  │ │  ┌───────────────┐  │
│  │ Availability  │  │ │  │ Availability  │  │ │  │ Availability  │  │
│  │   Service     │  │ │  │   Service     │  │ │  │   Service     │  │
│  └───────────────┘  │ │  └───────────────┘  │ │  └───────────────┘  │
│  ┌───────────────┐  │ │  ┌───────────────┐  │ │  ┌───────────────┐  │
│  │    Order      │  │ │  │    Order      │  │ │  │    Order      │  │
│  │   Service     │  │ │  │   Service     │  │ │  │   Service     │  │
│  └───────────────┘  │ │  └───────────────┘  │ │  └───────────────┘  │
└─────────────────────┘ └─────────────────────┘ └─────────────────────┘
              │                     │                     │
              └─────────────────────┼─────────────────────┘
                                    │
                                    ▼
                    ┌─────────────────────────────────┐
                    │     SHARED DATA STORES          │
                    │                                 │
                    │  • Amazon ElastiCache (Redis)   │
                    │  • Amazon OpenSearch Service    │
                    │  • Amazon RDS (PostgreSQL)      │
                    │  • Amazon SQS                   │
                    └─────────────────────────────────┘
```

### How They Communicate (Same VPC)

All EC2 instances are in the **same VPC (Virtual Private Cloud)**:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        VPC (10.0.0.0/16)                            │
│                                                                     │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │              PUBLIC SUBNET (10.0.1.0/24)                    │   │
│   │                                                             │   │
│   │   ┌──────────┐  ┌──────────┐  ┌──────────┐                  │   │
│   │   │   EC2    │  │   EC2    │  │   EC2    │    ← API servers │   │
│   │   └──────────┘  └──────────┘  └──────────┘                  │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                    Private IP communication                         │
│                              │                                      │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │              PRIVATE SUBNET (10.0.2.0/24)                   │   │
│   │                                                             │   │
│   │   ┌──────────┐  ┌──────────┐  ┌──────────┐                  │   │
│   │   │   RDS    │  │  Redis   │  │OpenSearch│   ← Databases    │   │
│   │   └──────────┘  └──────────┘  └──────────┘                  │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Points:**
- **Same VPC**: All resources can talk via private IPs (10.0.x.x)
- **Security Groups**: Act as firewalls controlling what can talk to what
- **No Public Internet**: Database traffic stays internal

---

### Option 2: Kubernetes on EC2 (K3s - What We Use)

```
┌─────────────────────────────────────────────────────────────────────┐
│                     K3s CLUSTER (on EC2)                            │
│                                                                     │
│   ┌──────────────────────────────────────────────────────────────┐  │
│   │                    MASTER NODE (EC2)                         │  │
│   │                                                              │  │
│   │   • K3s Control Plane                                        │  │
│   │   • Kubectl API Server                                       │  │
│   │   • Schedules pods to workers                                │  │
│   └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│              ┌───────────────┼───────────────┐                      │
│              │               │               │                      │
│              ▼               ▼               ▼                      │
│   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐               │
│   │  WORKER 1    │ │  WORKER 2    │ │  WORKER 3    │               │
│   │              │ │              │ │              │               │
│   │ ┌──────────┐ │ │ ┌──────────┐ │ │ ┌──────────┐ │               │
│   │ │Avail Pod │ │ │ │Order Pod │ │ │ │Fulfill   │ │               │
│   │ │(replica) │ │ │ │(replica) │ │ │ │Worker    │ │               │
│   │ └──────────┘ │ │ └──────────┘ │ │ └──────────┘ │               │
│   │ ┌──────────┐ │ │ ┌──────────┐ │ │              │               │
│   │ │Avail Pod │ │ │ │Order Pod │ │ │              │               │
│   │ │(replica) │ │ │ │(replica) │ │ │              │               │
│   │ └──────────┘ │ │ └──────────┘ │ │              │               │
│   └──────────────┘ └──────────────┘ └──────────────┘               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Kubernetes Benefits:**
- Auto-scaling with HPA (Horizontal Pod Autoscaler)
- Self-healing (restarts failed containers)
- Rolling updates (zero-downtime deployments)
- Service discovery (pods find each other by name)

---

## How Services Communicate in a Cluster

### 1. **Kubernetes Services (ClusterIP)**
```yaml
# availability-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: availability-service
spec:
  selector:
    app: availability
  ports:
    - port: 8000
      targetPort: 8000
```

Now any pod can call `http://availability-service:8000`

### 2. **Environment Variables**
```yaml
# order-service deployment
env:
  - name: AVAILABILITY_URL
    value: "http://availability-service:8000"
  - name: DB_HOST
    value: "postgres.default.svc.cluster.local"
```

### 3. **Ingress Controller (for external traffic)**
```
Internet → ALB → Ingress Controller → Services → Pods
```

---

## Scaling Strategies

### Auto Scaling EC2 (ASG)
```
┌───────────────────────────────────────────────────────────┐
│              Auto Scaling Group                           │
│                                                           │
│   Scale OUT when: CPU > 70% for 5 minutes                 │
│   Scale IN when:  CPU < 30% for 10 minutes                │
│                                                           │
│   Min: 2 instances                                        │
│   Max: 10 instances                                       │
│   Desired: 3 instances (adjusts automatically)            │
└───────────────────────────────────────────────────────────┘
```

### Kubernetes HPA
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: availability-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: availability-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

---

## Future Enhancements

### 1. **API Gateway (AWS API Gateway)**
- Rate limiting
- Authentication
- Request/response transformation
- Caching

### 2. **Service Mesh (Istio/Linkerd)**
- mTLS between services
- Observability (tracing, metrics)
- Traffic management (canary, A/B testing)

### 3. **Event-Driven Architecture**
```
                ┌─────────────┐
                │  EventBridge│
                │   or SNS    │
                └──────┬──────┘
                       │
       ┌───────────────┼───────────────┐
       │               │               │
       ▼               ▼               ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ Notification│ │  Analytics  │ │   Audit     │
│   Service   │ │   Service   │ │   Service   │
└─────────────┘ └─────────────┘ └─────────────┘
```

### 4. **Caching Layer (CloudFront + API Cache)**
```
User → CloudFront CDN → API Gateway Cache → Backend
         (edge cache)    (response cache)
```

### 5. **Multi-Region Deployment**
```
┌─────────────────┐         ┌─────────────────┐
│  us-east-1      │ ←──────→│  ap-south-1     │
│  (Virginia)     │  Route53│  (Mumbai)       │
│                 │ Latency │                 │
│  Full Stack     │ Routing │  Full Stack     │
└─────────────────┘         └─────────────────┘
```

---

## Summary: Your Architecture is Production-Ready!

| Component | Local (Docker) | AWS (Production) |
|-----------|----------------|------------------|
| Container Orchestration | Docker Compose | K3s/EKS |
| Load Balancer | Nginx | AWS ALB |
| Database | PostgreSQL container | Amazon RDS |
| Cache | Redis container | ElastiCache |
| Search | OpenSearch container | Amazon OpenSearch |
| Queue | Mock (console log) | Amazon SQS |
| Auto-scaling | Manual | ASG + HPA |

**You've built a cloud-native application that can scale from 10 users to 10 million users by just adding more instances behind a load balancer!** 🚀
