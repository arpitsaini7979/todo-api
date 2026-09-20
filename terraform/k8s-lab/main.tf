# Temporary Kubernetes lab: ONE t3.medium running k3s, separate from the
# production todo-api instance in ../main.tf (own state key, own security group).
# Destroy it when you are done: `terraform destroy`.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Same bucket as the main config, different key, so the two never share state.
  backend "s3" {
    bucket       = "todo-api-tfstate-475369996910"
    key          = "k8s-lab/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "todo-api-k8s-lab"
      ManagedBy = "terraform"
    }
  }
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair, used for SSH access"
  type        = string
}

variable "instance_type" {
  description = "Must be free-plan eligible (t3.medium is not). c7i-flex.large = 2 vCPU / 4 GB; use m7i-flex.large (8 GB) if ArgoCD needs more room."
  type        = string
  default     = "c7i-flex.large"
}

variable "ssh_cidr_blocks" {
  description = "Who may reach SSH and the NodePort. No default on purpose: pass your own IP as a /32, e.g. [\"1.2.3.4/32\"]."
  type        = list(string)
}

variable "k3s_version" {
  description = "Pinned k3s release installed on first boot"
  type        = string
  default     = "v1.36.2+k3s1"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "k8s_lab" {
  name        = "k8s-lab-sg"
  description = "SSH and the NodePort for the k3s lab, restricted to ssh_cidr_blocks"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  # Matches nodePort in k8s/service.yaml
  ingress {
    description = "To-Do API NodePort"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-lab-sg"
  }
}

resource "aws_instance" "k8s_lab" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.k8s_lab.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2          # pods sit one hop behind the node
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  # k3s runs as a systemd service with its own embedded containerd, so Docker
  # is not needed. --write-kubeconfig-mode 644 lets ec2-user run kubectl
  # without sudo. Progress is logged to /var/log/k3s-install.log.
  user_data = <<-EOF
    #!/bin/bash
    exec > /var/log/k3s-install.log 2>&1
    set -ex

    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='${var.k3s_version}' \
      INSTALL_K3S_EXEC='server --write-kubeconfig-mode 644' sh -

    echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /home/ec2-user/.bashrc
    mkdir -p /home/ec2-user/k8s
    chown ec2-user:ec2-user /home/ec2-user/k8s
  EOF

  tags = {
    Name = "k8s-lab"
  }
}

output "instance_public_ip" {
  description = "Public IP of the lab instance (changes if you stop/start it)"
  value       = aws_instance.k8s_lab.public_ip
}

output "ssh_command" {
  value = "ssh -i ~/todo-api-key-v2.pem ec2-user@${aws_instance.k8s_lab.public_ip}"
}
