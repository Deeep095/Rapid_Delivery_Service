# Terraform Local Setup - Cost Saving Configuration

## Overview
This Terraform configuration runs **PostgreSQL, Redis, and OpenSearch locally on EC2** using Docker containers instead of AWS managed services.

## Cost Savings
| Service | AWS Managed Cost | Local (Docker) Cost | Monthly Savings |
|---------|------------------|---------------------|-----------------|
| OpenSearch (t3.small.search) | ~$30/month | $0 (runs on EC2) | **$30** |
| RDS PostgreSQL (db.t3.micro) | ~$15-20/month | $0 (runs on EC2) | **$15-20** |
| ElastiCache Redis (cache.t2.micro) | ~$12-15/month | $0 (runs on EC2) | **$12-15** |
| **TOTAL SAVINGS** | | | **~$55-65/month** |

## What's Still on AWS (Free Tier)
- **EC2 t3.small** - Runs K3s + Docker containers for DBs
- **SQS** - Order queue (1M requests/month free)
- **SNS** - Notifications (1M requests/month free)
- **ECR** - Container registry (500MB free)

## Architecture
```
┌─────────────────────────────────────────────────────────┐
│                    EC2 t3.small                          │
│  ┌─────────────────────────────────────────────────────┐│
│  │                   Docker                            ││
│  │  ┌─────────────┐ ┌─────────┐ ┌──────────────────┐  ││
│  │  │ PostgreSQL  │ │  Redis  │ │   OpenSearch     │  ││
│  │  │   :5432     │ │  :6379  │ │     :9200        │  ││
│  │  └─────────────┘ └─────────┘ └──────────────────┘  ││
│  └─────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────┐│
│  │                    K3s                              ││
│  │  ┌────────────┐ ┌────────────┐ ┌─────────────────┐ ││
│  │  │Availability│ │   Order    │ │   Fulfillment   │ ││
│  │  │  Service   │ │  Service   │ │     Worker      │ ││
│  │  └────────────┘ └────────────┘ └─────────────────┘ ││
│  └─────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────┐│
│  │              Nginx (Port 80)                        ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
              │
              ▼
     ┌────────────────┐
     │   SQS Queue    │  (AWS - Free Tier)
     │   SNS Topic    │
     └────────────────┘
```

## Usage

### 1. First, destroy expensive AWS services from old setup
```powershell
cd ../terraform-files
terraform destroy -target=aws_opensearch_domain.search -target=aws_db_instance.postgres -target=aws_elasticache_cluster.redis
```

### 2. Deploy the local setup
```powershell
cd ../terraform-local
terraform init
terraform plan
terraform apply
```

### 3. Seed the local databases
```bash
# SSH into EC2
ssh -i k3s-key ubuntu@<EC2_PUBLIC_IP>

# Seed OpenSearch with warehouses
curl -X PUT "http://localhost:9200/warehouses" -H 'Content-Type: application/json' -d '{
  "mappings": {
    "properties": {
      "name": {"type": "text"},
      "location": {"type": "geo_point"},
      "inventory": {"type": "object"}
    }
  }
}'
```

## Files
- `main.tf` - Provider and data sources
- `networking.tf` - VPC and Security Groups
- `compute.tf` - EC2 instances with Docker
- `queues.tf` - SQS and SNS (remain on AWS)
- `ecr.tf` - ECR repositories
- `user_data_api.sh` - Bootstrap script for master node
- `user_data_worker.sh` - Bootstrap script for worker node
- `variables.tf` - Input variables
- `outputs.tf` - Output values

## Switching Back to AWS Managed Services
If you want to switch back to AWS managed services (RDS, ElastiCache, OpenSearch):
1. Go to `terraform-files` folder
2. Run `terraform apply`

The original AWS setup is preserved in `terraform-files/`.
