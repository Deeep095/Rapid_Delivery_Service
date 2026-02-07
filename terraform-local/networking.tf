# =============================================================================
# NETWORKING - VPC and Security Groups
# No AWS managed services - just networking for EC2
# =============================================================================

# Use Default VPC (free)
resource "aws_default_vpc" "default" {
  tags = { Name = "Default VPC" }
}

# Security Group for EC2 instances
resource "aws_security_group" "rapid_delivery_sg" {
  name        = "rapid-delivery-local-sg"
  description = "Security group for local setup with Docker DBs"
  vpc_id      = aws_default_vpc.default.id

  # SSH Access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # HTTP (Nginx reverse proxy)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP - Nginx reverse proxy"
  }

  # Kubernetes NodePort services
  ingress {
    from_port   = 30001
    to_port     = 30002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes NodePort services"
  }

  # K3s API server (cluster internal)
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    self        = true
    description = "K3s API server - cluster internal"
  }

  # Flannel VXLAN for K3s networking
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
    description = "K3s Flannel VXLAN"
  }

  # Kubelet metrics
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
    description = "K3s Kubelet metrics"
  }

  # All internal communication
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "All internal traffic"
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rapid-delivery-local-sg"
  }
}
