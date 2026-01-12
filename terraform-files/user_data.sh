#!/bin/bash
set -e

############################
# 0. Swap (critical for t2.micro)
############################
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

############################
# 1. Install dependencies
############################
apt-get update
apt-get install -y curl unzip docker.io

systemctl enable docker
systemctl start docker

############################
# 2. Install k3s with optimized configuration for low-resource environment
############################
# Create k3s config directory
mkdir -p /etc/rancher/k3s

# Configure k3s for low-resource environment
cat <<EOF > /etc/rancher/k3s/config.yaml
---
kubelet-arg:
  - "max-pods=10"
  - "eviction-hard=memory.available<100Mi"
  - "eviction-soft=memory.available<200Mi"
  - "eviction-soft-grace-period=memory.available=30s"
EOF

# Install k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -

sleep 30

############################
# 3. Install AWS CLI
############################
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

############################
# 4. Configure kubectl
############################
mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config

############################
# 5. Login to ECR (Docker auth)
############################
aws ecr get-login-password --region ${AWS_REGION} \
 | docker login --username AWS \
 --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

############################
# 6. Create Kubernetes imagePullSecret
############################
k3s kubectl create secret docker-registry ecr-secret \
  --docker-server=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region ${AWS_REGION})" \
  --dry-run=client -o yaml | k3s kubectl apply -f -

############################
# 7. Create ConfigMap and Secret
############################
mkdir -p /opt/k8s

# Create ConfigMap with application configuration
k3s kubectl create configmap app-config \
  --from-literal=redis-endpoint="${REDIS_ENDPOINT}" \
  --from-literal=db-endpoint="${DB_ENDPOINT}" \
  --from-literal=sqs-queue-url="${SQS_QUEUE_URL}" \
  --from-literal=opensearch-endpoint="https://${OPENSEARCH_ENDPOINT}" \
  --dry-run=client -o yaml | k3s kubectl apply -f -

# Create Secret with DB credentials
k3s kubectl create secret generic db-credentials \
  --from-literal=password="password123" \
  --dry-run=client -o yaml | k3s kubectl apply -f -

############################
# 8. Create Deployment YAML with Resource Limits
############################
cat <<EOF > /opt/k8s/app.yaml
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
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
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
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /
            port: 8001
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /
            port: 8001
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
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
      containers:
      - name: fulfillment
        image: ${FULFILLMENT_IMAGE_URL}:latest
        env:
        - name: AWS_REGION
          value: "${AWS_REGION}"
        - name: SQS_QUEUE_URL
          value: "${SQS_QUEUE_URL}"
        - name: DB_HOST
          value: "${DB_ENDPOINT}"
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
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - "ps aux | grep '[p]ython.*main.py' || exit 1"
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
EOF

############################
# 9. Apply to cluster
############################
sleep 30
k3s kubectl apply -f /opt/k8s/app.yaml

# Wait for deployments to be ready
k3s kubectl wait --for=condition=available --timeout=300s deployment/availability-app
k3s kubectl wait --for=condition=available --timeout=300s deployment/order-app
k3s kubectl wait --for=condition=available --timeout=300s deployment/fulfillment-worker

# Show pod status
k3s kubectl get pods -A
