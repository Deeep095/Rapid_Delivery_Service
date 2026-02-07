#!/bin/bash
set -e
# Swap for t3.micro
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Install deps
apt-get update && apt-get install -y curl unzip docker.io nginx
systemctl enable docker && systemctl start docker

# AWS CLI
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip && ./aws/install

# Local DBs (Docker)
mkdir -p /data/postgres /data/redis /data/opensearch && chmod 777 /data/opensearch

docker run -d --name postgres --restart unless-stopped \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=${DB_PASSWORD} -e POSTGRES_DB=postgres \
  -v /data/postgres:/var/lib/postgresql/data -p 5432:5432 postgres:15-alpine

docker run -d --name redis --restart unless-stopped \
  -v /data/redis:/data -p 6379:6379 redis:7-alpine redis-server --appendonly yes

docker run -d --name opensearch --restart unless-stopped \
  -e "discovery.type=single-node" -e "plugins.security.disabled=true" \
  -e "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m" \
  -v /data/opensearch:/usr/share/opensearch/data -p 9200:9200 opensearchproject/opensearch:2.11.0

sleep 30
until docker exec postgres pg_isready -U postgres; do sleep 5; done
until docker exec redis redis-cli ping | grep -q PONG; do sleep 5; done
until curl -s http://localhost:9200 | grep -q "cluster_name"; do sleep 10; done

# K3s
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
mkdir -p /etc/rancher/k3s
cat <<EOF > /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: "0644"
tls-san: ["$PRIVATE_IP"]
node-label: ["node-role=master"]
kubelet-arg: ["max-pods=10","eviction-hard=memory.available<100Mi"]
EOF

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --disable servicelb" sh -
sleep 45
until k3s kubectl get nodes | grep -q " Ready"; do sleep 10; done

# SSM params
K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
aws ssm put-parameter --name "/rapid-delivery-local/k3s-token" --value "$K3S_TOKEN" --type "SecureString" --overwrite --region ${AWS_REGION}
aws ssm put-parameter --name "/rapid-delivery-local/k3s-master-ip" --value "$PRIVATE_IP" --type "String" --overwrite --region ${AWS_REGION}

mkdir -p /root/.kube && cp /etc/rancher/k3s/k3s.yaml /root/.kube/config

# ECR login
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# K8s secrets
k3s kubectl create secret docker-registry ecr-secret \
  --docker-server=${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region ${AWS_REGION})" --dry-run=client -o yaml | k3s kubectl apply -f -

k3s kubectl create secret generic db-credentials --from-literal=password="${DB_PASSWORD}" --dry-run=client -o yaml | k3s kubectl apply -f -

k3s kubectl create configmap app-config \
  --from-literal=redis-endpoint="$PRIVATE_IP" --from-literal=db-endpoint="$PRIVATE_IP" \
  --from-literal=sqs-queue-url="${SQS_QUEUE_URL}" --from-literal=sns-topic-arn="${SNS_TOPIC_ARN}" \
  --from-literal=opensearch-endpoint="http://$PRIVATE_IP:9200" --dry-run=client -o yaml | k3s kubectl apply -f -

# Deploy services
mkdir -p /opt/k8s
cat <<'EOFYAML' > /opt/k8s/all-services.yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: availability-app}
spec:
  replicas: 1
  selector: {matchLabels: {app: availability}}
  template:
    metadata: {labels: {app: availability}}
    spec:
      imagePullSecrets: [{name: ecr-secret}]
      containers:
      - name: availability
        image: AVAIL_IMAGE_PLACEHOLDER:latest
        ports: [{containerPort: 8000}]
        env:
        - {name: AWS_REGION, value: "AWS_REGION_PLACEHOLDER"}
        - {name: OPENSEARCH_URL, valueFrom: {configMapKeyRef: {name: app-config, key: opensearch-endpoint}}}
        - {name: REDIS_HOST, valueFrom: {configMapKeyRef: {name: app-config, key: redis-endpoint}}}
        - {name: REDIS_PORT, value: "6379"}
        resources: {requests: {memory: "150Mi", cpu: "100m"}, limits: {memory: "300Mi", cpu: "500m"}}
---
apiVersion: v1
kind: Service
metadata: {name: availability-service}
spec: {type: NodePort, selector: {app: availability}, ports: [{port: 8000, targetPort: 8000, nodePort: 30001}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: order-app}
spec:
  replicas: 1
  selector: {matchLabels: {app: order}}
  template:
    metadata: {labels: {app: order}}
    spec:
      imagePullSecrets: [{name: ecr-secret}]
      containers:
      - name: order
        image: ORDER_IMAGE_PLACEHOLDER:latest
        ports: [{containerPort: 8001}]
        env:
        - {name: AWS_REGION, value: "AWS_REGION_PLACEHOLDER"}
        - {name: SQS_QUEUE_URL, value: "SQS_QUEUE_PLACEHOLDER"}
        - {name: SNS_TOPIC_ARN, value: "SNS_TOPIC_PLACEHOLDER"}
        - {name: DB_HOST, valueFrom: {configMapKeyRef: {name: app-config, key: db-endpoint}}}
        - {name: DB_PORT, value: "5432"}
        - {name: DB_NAME, value: "postgres"}
        - {name: DB_USER, value: "postgres"}
        - {name: DB_PASS, valueFrom: {secretKeyRef: {name: db-credentials, key: password}}}
        resources: {requests: {memory: "150Mi", cpu: "100m"}, limits: {memory: "300Mi", cpu: "500m"}}
---
apiVersion: v1
kind: Service
metadata: {name: order-service}
spec: {type: NodePort, selector: {app: order}, ports: [{port: 8001, targetPort: 8001, nodePort: 30002}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: fulfillment-worker}
spec:
  replicas: 1
  selector: {matchLabels: {app: fulfillment}}
  template:
    metadata: {labels: {app: fulfillment}}
    spec:
      imagePullSecrets: [{name: ecr-secret}]
      containers:
      - name: fulfillment
        image: FULFILLMENT_IMAGE_PLACEHOLDER:latest
        env:
        - {name: AWS_REGION, value: "AWS_REGION_PLACEHOLDER"}
        - {name: SQS_QUEUE_URL, value: "SQS_QUEUE_PLACEHOLDER"}
        - {name: DB_HOST, valueFrom: {configMapKeyRef: {name: app-config, key: db-endpoint}}}
        - {name: DB_NAME, value: "postgres"}
        - {name: DB_USER, value: "postgres"}
        - {name: DB_PASS, valueFrom: {secretKeyRef: {name: db-credentials, key: password}}}
        - {name: REDIS_HOST, valueFrom: {configMapKeyRef: {name: app-config, key: redis-endpoint}}}
        - {name: REDIS_PORT, value: "6379"}
        resources: {requests: {memory: "100Mi", cpu: "50m"}, limits: {memory: "200Mi", cpu: "300m"}}
EOFYAML

# Replace placeholders
sed -i "s|AVAIL_IMAGE_PLACEHOLDER|${AVAIL_IMAGE_URL}|g" /opt/k8s/all-services.yaml
sed -i "s|ORDER_IMAGE_PLACEHOLDER|${ORDER_IMAGE_URL}|g" /opt/k8s/all-services.yaml
sed -i "s|FULFILLMENT_IMAGE_PLACEHOLDER|${FULFILLMENT_IMAGE_URL}|g" /opt/k8s/all-services.yaml
sed -i "s|AWS_REGION_PLACEHOLDER|${AWS_REGION}|g" /opt/k8s/all-services.yaml
sed -i "s|SQS_QUEUE_PLACEHOLDER|${SQS_QUEUE_URL}|g" /opt/k8s/all-services.yaml
sed -i "s|SNS_TOPIC_PLACEHOLDER|${SNS_TOPIC_ARN}|g" /opt/k8s/all-services.yaml

sleep 30
k3s kubectl apply -f /opt/k8s/all-services.yaml

# Nginx
cat <<'EOFNGINX' > /etc/nginx/sites-available/k8s-proxy
server {
    listen 80;
    server_name _;
    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Methods' 'GET,POST,PUT,DELETE,OPTIONS,PATCH' always;
    add_header 'Access-Control-Allow-Headers' 'Content-Type,Authorization,Accept,Origin' always;
    location /availability/ { rewrite ^/availability/(.*)$ /$1 break; proxy_pass http://127.0.0.1:30001; }
    location /warehouses { proxy_pass http://127.0.0.1:30001/warehouses; }
    location /inventory/ { proxy_pass http://127.0.0.1:30001/inventory/; }
    location /order/ { rewrite ^/order/(.*)$ /$1 break; proxy_pass http://127.0.0.1:30002; }
    location /subscribe { proxy_pass http://127.0.0.1:30002/subscribe; }
    location /health { return 200 'OK'; }
    location / { proxy_pass http://127.0.0.1:30001; }
}
EOFNGINX
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/k8s-proxy /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx && systemctl enable nginx
echo "Setup complete! PostgreSQL:5432 Redis:6379 OpenSearch:9200"
