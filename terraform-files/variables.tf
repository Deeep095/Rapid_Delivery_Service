variable "my_ip" {
  description = "Your local IP address (for SSH access)"
  type        = string
}

variable "db_password" {
  description = "Password for the RDS database"
  type        = string
  sensitive   = true
}

variable "public_key_path" {
  description = "Path to your SSH public key"
  type        = string
  default     = "k3s-key.pub"
}

variable "aws-region" {
  description = "region of the deployment aws"
  type        = string
  default     = "us-east-1"
  
}