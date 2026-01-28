#!/bin/bash
set -e

echo "=========================================="
echo "K3S MASTER NODE - API Services + Local DBs"
echo "=========================================="

############################
# 0. Swap (critical for t3.small with local DBs)
############################
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

############################
# 1. Install dependencies
############################
apt-get update
apt-get install -y curl unzip docker.io nginx

systemctl enable docker
systemctl start docker

############################
# 2. Install AWS CLI
############################
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

############################
# 3. Start Local Databases (Docker) - REPLACES AWS RDS/ElastiCache/OpenSearch
############################
echo "Starting local databases via Docker..."

# Create data directories
mkdir -p /data/postgres /data/redis /data/opensearch
chmod 777 /data/opensearch

# PostgreSQL (replaces RDS)
docker run -d \
  --name postgres \
  --restart unless-stopped \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=password123 \
  -e POSTGRES_DB=postgres \
  -v /data/postgres:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres:15-alpine

# Redis (replaces ElastiCache)
docker run -d \
  --name redis \
  --restart unless-stopped \
  -v /data/redis:/data \
  -p 6379:6379 \
  redis:7-alpine

# OpenSearch (replaces AWS OpenSearch - saves ~$30/month!)
docker run -d \
  --name opensearch \
  --restart unless-stopped \
  -e "discovery.type=single-node" \
  -e "plugins.security.disabled=true" \
  -e "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m" \
  -v /data/opensearch:/usr/share/opensearch/data \
  -p 9200:9200 \
  opensearchproject/opensearch:2.11.0

# Wait for databases to be ready
echo "Waiting for databases to start..."
sleep 30

# Check database health
until docker exec postgres pg_isready -U postgres; do
  echo "Waiting for PostgreSQL..."
  sleep 5
done
echo "PostgreSQL is ready!"

until docker exec redis redis-cli ping | grep -q PONG; do
  echo "Waiting for Redis..."
  sleep 5
done
echo "Redis is ready!"

until curl -s http://localhost:9200 | grep -q "cluster_name"; do
  echo "Waiting for OpenSearch..."
  sleep 10
done
echo "OpenSearch is ready!"

############################
# 4. Install K3s SERVER (Master)
############################
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

mkdir -p /etc/rancher/k3s
cat <<EOF > /etc/rancher/k3s/config.yaml
---
write-kubeconfig-mode: "0644"
tls-san:
  - "$PRIVATE_IP"
node-label:
  - "node-role=master"
kubelet-arg:
  - "max-pods=10"
  - "eviction-hard=memory.available<100Mi"
  - "eviction-soft=memory.available<200Mi"
  - "eviction-soft-grace-period=memory.available=30s"
EOF

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --disable servicelb" sh -

echo "Waiting for K3s to start..."
sleep 45

until k3s kubectl get nodes | grep -q " Ready"; do
  echo "Waiting for node to be ready..."
  sleep 10
done

############################
# 5. Save K3s token to SSM for worker node
############################
K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
aws ssm put-parameter \
  --name "/rapid-delivery/k3s-token" \
  --value "$K3S_TOKEN" \
  --type "SecureString" \
  --overwrite \
  --region ${AWS_REGION}

aws ssm put-parameter \
  --name "/rapid-delivery/k3s-master-ip" \
  --value "$PRIVATE_IP" \
  --type "String" \
  --overwrite \
  --region ${AWS_REGION}

echo "K3s token saved to SSM Parameter Store"

############################
# 6. Configure kubectl
############################
mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config

############################
# 7. Login to ECR
############################
aws ecr get-login-password --region ${AWS_REGION} \
 | docker login --username AWS \
 --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

############################
# 8. Create imagePullSecret
############################
k3s kubectl create secret docker-registry ecr-secret \
  --docker-server=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region ${AWS_REGION})" \
  --dry-run=client -o yaml | k3s kubectl apply -f -

############################
# 9. Create ConfigMap and Secret (LOCAL ENDPOINTS)
############################
k3s kubectl create secret generic db-credentials \
  --from-literal=password="password123" \
  --dry-run=client -o yaml | k3s kubectl apply -f -

# Use private IP for K8s pods to reach host Docker services
k3s kubectl create configmap app-config \
  --from-literal=redis-endpoint="$PRIVATE_IP" \
  --from-literal=db-endpoint="$PRIVATE_IP" \
  --from-literal=sqs-queue-url="${SQS_QUEUE_URL}" \
  --from-literal=sns-topic-arn="${SNS_TOPIC_ARN}" \
  --from-literal=opensearch-endpoint="http://$PRIVATE_IP:9200" \
  --dry-run=client -o yaml | k3s kubectl apply -f -

############################
# 10. Deploy ALL Services
############################
mkdir -p /opt/k8s

cat <<EOF > /opt/k8s/all-services.yaml
# ===== AVAILABILITY SERVICE =====
apiVersion: apps/v1
kind: Deployment
metadata:
  name: availability-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: availability
  template:
    metadata:
      labels:
        app: availability
    spec:
      imagePullSecrets:
      - name: ecr-secret
      containers:
      - name: availability
        image: ${AVAIL_IMAGE_URL}:latest
        ports:
        - containerPort: 8000
        env:
        - name: AWS_REGION
          value: "${AWS_REGION}"
        - name: OPENSEARCH_URL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: opensearch-endpoint
        - name: REDIS_HOST
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: redis-endpoint
        - name: REDIS_PORT
          value: "6379"
        resources:
          requests:
            memory: "150Mi"
            cpu: "100m"
          limits:
            memory: "300Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /
            port: 8000
          initialDelaySeconds: 60
          periodSeconds: 15
        readinessProbe:
          httpGet:
            path: /
            port: 8000
          initialDelaySeconds: 20
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: availability-service
spec:
  type: NodePort
  selector:
    app: availability
  ports:
  - port: 8000
    targetPort: 8000
    nodePort: 30001
---
# ===== ORDER SERVICE =====
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: order
  template:
    metadata:
      labels:
        app: order
    spec:
      imagePullSecrets:
      - name: ecr-secret
      containers:
      - name: order
        image: ${ORDER_IMAGE_URL}:latest
        ports:
        - containerPort: 8001
        env:
        - name: AWS_REGION
          value: "${AWS_REGION}"
        - name: SQS_QUEUE_URL
          value: "${SQS_QUEUE_URL}"
        - name: SNS_TOPIC_ARN
          value: "${SNS_TOPIC_ARN}"
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: db-endpoint
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "postgres"
        - name: DB_USER
          value: "postgres"
        - name: DB_PASS
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        resources:
          requests:
            memory: "150Mi"
            cpu: "100m"
          limits:
            memory: "300Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /
            port: 8001
          initialDelaySeconds: 60
          periodSeconds: 15
        readinessProbe:
          httpGet:
            path: /
            port: 8001
          initialDelaySeconds: 20
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: order-service
spec:
  type: NodePort
  selector:
    app: order
  ports:
  - port: 8001
    targetPort: 8001
    nodePort: 30002
---
# ===== FULFILLMENT WORKER =====
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fulfillment-worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fulfillment
  template:
    metadata:
      labels:
        app: fulfillment
    spec:
      imagePullSecrets:
      - name: ecr-secret
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: node-role
                operator: In
                values:
                - worker
      containers:
      - name: fulfillment
        image: ${FULFILLMENT_IMAGE_URL}:latest
        env:
        - name: AWS_REGION
          value: "${AWS_REGION}"
        - name: SQS_QUEUE_URL
          value: "${SQS_QUEUE_URL}"
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: db-endpoint
        - name: DB_NAME
          value: "postgres"
        - name: DB_USER
          value: "postgres"
        - name: DB_PASS
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        - name: REDIS_HOST
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: redis-endpoint
        - name: REDIS_PORT
          value: "6379"
        resources:
          requests:
            memory: "100Mi"
            cpu: "50m"
          limits:
            memory: "200Mi"
            cpu: "300m"
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - "ps aux | grep '[p]ython.*main.py' || exit 1"
          initialDelaySeconds: 90
          periodSeconds: 30
EOF

############################
# 10. Apply deployments
############################
sleep 30
k3s kubectl apply -f /opt/k8s/all-services.yaml

# Wait for API services (worker can take longer)
k3s kubectl wait --for=condition=available --timeout=300s deployment/availability-app || true
k3s kubectl wait --for=condition=available --timeout=300s deployment/order-app || true

############################
# 11. Configure Nginx Reverse Proxy (Port 80) with Enhanced CORS
############################
cat <<EOF > /etc/nginx/sites-available/k8s-proxy
server {
    listen 80;
    server_name _;

    # Enhanced CORS headers for Flutter Web (applied to all responses)
    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS, PATCH' always;
    add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,Accept,Origin' always;
    add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range,Content-Type' always;
    add_header 'Access-Control-Max-Age' 86400 always;

    # Availability Service
    location /availability/ {
        # Handle CORS preflight
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS, PATCH';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,Accept,Origin';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range,Content-Type';
            add_header 'Access-Control-Max-Age' 86400;
            add_header 'Content-Length' 0;
            add_header 'Content-Type' 'text/plain';
            return 204;
        }
        
        rewrite ^/availability/(.*)\$ /\$1 break;
        proxy_pass http://127.0.0.1:30001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Warehouses API (Manager Dashboard)
    location /warehouses {
        # Handle CORS preflight
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS, PATCH';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,Accept,Origin';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range,Content-Type';
            add_header 'Access-Control-Max-Age' 86400;
            add_header 'Content-Length' 0;
            add_header 'Content-Type' 'text/plain';
            return 204;
        }
        
        proxy_pass http://127.0.0.1:30001/warehouses;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Inventory API (Manager Dashboard)
    location /inventory/ {
        # Handle CORS preflight
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS, PATCH';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,Accept,Origin';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range,Content-Type';
            add_header 'Access-Control-Max-Age' 86400;
            add_header 'Content-Length' 0;
            add_header 'Content-Type' 'text/plain';
            return 204;
        }
        
        proxy_pass http://127.0.0.1:30001/inventory/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Order Service
    location /order/ {
        # Handle CORS preflight
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS, PATCH';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,Accept,Origin';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range,Content-Type';
            add_header 'Access-Control-Max-Age' 86400;
            add_header 'Content-Length' 0;
            add_header 'Content-Type' 'text/plain';
            return 204;
        }
        
        rewrite ^/order/(.*)\$ /\$1 break;
        proxy_pass http://127.0.0.1:30002;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Subscribe endpoint for SNS notifications
    location /subscribe {
        # Handle CORS preflight
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS, PATCH';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization,Accept,Origin';
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range,Content-Type';
            add_header 'Access-Control-Max-Age' 86400;
            add_header 'Content-Length' 0;
            add_header 'Content-Type' 'text/plain';
            return 204;
        }
        
        proxy_pass http://127.0.0.1:30002/subscribe;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # Health check
    location /health {
        add_header 'Access-Control-Allow-Origin' '*' always;
        return 200 'OK';
        add_header Content-Type text/plain;
    }

    # Default: Availability service
    location / {
        proxy_pass http://127.0.0.1:30001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/k8s-proxy /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx
systemctl enable nginx

echo "✅ K3s Master Node Ready!"
echo "API accessible on port 80 via Nginx"
k3s kubectl get nodes
k3s kubectl get pods -A
