# =============================================================================
# TERRAFORM LOCAL SETUP - Cost Saving Configuration
# Runs PostgreSQL, Redis, OpenSearch on EC2 via Docker instead of AWS services
# SAVES: ~$55-65/month compared to AWS managed services
# =============================================================================

provider "aws" {
  region = var.aws_region
}

# Get current AWS Account ID
data "aws_caller_identity" "current" {}

# Get available Availability Zones
data "aws_availability_zones" "available" {}

# Ubuntu 22.04 LTS AMI (Official Canonical)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (official Ubuntu owner)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
