# 1. Create Repositories
resource "aws_ecr_repository" "availability_repo" {
  name         = "availability-service"
  force_delete = true
}

resource "aws_ecr_repository" "order_repo" {
  name         = "order-service"
  force_delete = true
}

# resource "aws_ecr_repository" "inventory_repo" {
#   name         = "inventory-worker"
#   force_delete = true
# }

resource "aws_ecr_repository" "fulfillment_repo" {
  name         = "fulfillment-worker"
  force_delete = true
}

# 2. Use null_resource to run Docker commands locally ***
resource "null_resource" "docker_build_push" {
  # Re-run this if any Dockerfile changes
  triggers = {
    always_run = timestamp() 
  }

  provisioner "local-exec" {
    # This command runs on Windows Laptop (PowerShell)
    interpreter = ["PowerShell", "-Command"]

    command = <<EOT
      # A. Login to AWS ECR
      # aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com
      aws ecr get-login-password --region ${var.aws-region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com
      # aws ecr get-login-password --region us-east-1 |docker login --username AWS --password-stdin 905418449359.dkr.ecr.us-east-1.amazonaws.com

      # B. Build & Push Availability Service
      cd ../availability-service
      docker build -t ${aws_ecr_repository.availability_repo.repository_url}:latest .
      docker push ${aws_ecr_repository.availability_repo.repository_url}:latest

      # C. Build & Push Order Service
      cd ../order-service
      docker build -t ${aws_ecr_repository.order_repo.repository_url}:latest .
      docker push ${aws_ecr_repository.order_repo.repository_url}:latest

      # D. Build & Push Fulfillment Worker
      cd ../fulfillment-worker
      docker build -t ${aws_ecr_repository.fulfillment_repo.repository_url}:latest .
      docker push ${aws_ecr_repository.fulfillment_repo.repository_url}:latest
    EOT
  }
}