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
# 2. Install k3s
############################
curl -sfL https://get.k3s.io | sh -

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
# 7. Create Deployment YAML
############################
mkdir -p /opt/k8s

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
        - name: OPENSEARCH_URL
          value: "https://${OPENSEARCH_ENDPOINT}"
        - name: REDIS_HOST
          value: "${REDIS_ENDPOINT}"
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
        - name: DB_HOST
          value: "${DB_ENDPOINT}"
        - name: AWS_REGION
          value: "${AWS_REGION}"
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
        - name: SQS_QUEUE_URL
          value: "${SQS_QUEUE_URL}"
        - name: AWS_REGION
          value: "${AWS_REGION}"
EOF

############################
# 8. Apply to cluster
############################
sleep 30
k3s kubectl apply -f /opt/k8s/app.yaml
