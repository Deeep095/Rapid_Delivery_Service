#!/bin/bash

# 1. Install basic setup and K3s (Lightweight Kubernetes)
apt-get update
apt-get install -y curl unzip

curl -sfL https://get.k3s.io | sh -

sleep 20
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

# 2. Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# 3. Create Kubernetes Manifests
mkdir -p /home/ubuntu/k8s
cat <<EOF > /home/ubuntu/k8s/deployment.yaml
# --- SERVICE 1: AVAILABILITY (Read Path) ---
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
      containers:
      - name: availability
        image: ${AVAIL_IMAGE_URL}
        ports:
        - containerPort: 8000
        env:
        - name: OPENSEARCH_URL
          value: "https://${OPENSEARCH_ENDPOINT}"
        - name: REDIS_HOST
          value: "${REDIS_ENDPOINT}"
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
    nodePort: 30001 # External Access Port

# --- SERVICE 2: ORDER (Write Path) ---
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
      containers:
      - name: order
        image: ${ORDER_IMAGE_URL}
        ports:
        - containerPort: 8001
        env:
        - name: DB_HOST
          value: "${DB_ENDPOINT}"
        - name: DB_PASS
          value: "password123"
        - name: DB_USER
          value: "postgres"
        - name: DB_NAME
          value: "postgres"
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


# --- SERVICE 3: FULFILLMENT WORKER (SQS Consumer) ---
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
      containers:
      - name: fulfillment
        image: ${FULFILLMENT_IMAGE_URL}
        env:
        - name: SQS_QUEUE_URL
          value: "${SQS_QUEUE_URL}"
        - name: DB_HOST
          value: "${DB_ENDPOINT}"
        - name: AWS_DEFAULT_REGION
          value: "${AWS_REGION}"
EOF

# 4. Apply to Kubernetes
# We wait 60s to ensure the DBs are fully initialized before the apps try to connect
sleep 60
sudo k3s kubectl apply -f /home/ubuntu/k8s/deployment.yaml