terraform {
  required_version = ">= 1.10" # backend.tf uses use_lockfile, added in 1.10

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "todo-api"
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
  description = "EC2 instance type. Must be free-plan eligible on new AWS accounts (t2.micro is not; t3.micro/t3.small are). t3.small = 2 vCPU / 2 GB, enough for the API, Postgres, Prometheus and Grafana."
  type        = string
  default     = "t3.small"
}

variable "ssh_cidr_blocks" {
  description = <<-EOT
    CIDRs allowed to SSH in. The CI deploy job connects from GitHub-hosted
    runners, whose IPs change, so this defaults to open. Narrow it to your own
    /32 once deploys move to SSM (or a self-hosted runner).
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "docker_compose_version" {
  description = "Docker Compose plugin version installed on first boot"
  type        = string
  default     = "v2.29.7"
}

# Always fetch the latest Amazon Linux 2023 AMI instead of hardcoding an ID,
# since AMI IDs are region-specific and change over time. The instance ignores
# AMI drift (see lifecycle below) so a new AMI never replaces the running box.
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

# Grafana (3001) and Prometheus (9090) are intentionally NOT exposed: the
# monitoring compose file binds them to 127.0.0.1 on the instance. Reach them
# through an SSH tunnel, e.g. `ssh -L 3001:localhost:3001 -L 9090:localhost:9090 ec2-user@<ip>`.
resource "aws_security_group" "todo_api_sg" {
  name        = "todo-api-sg"
  description = "Allow SSH and the To-Do API port to the To-Do API instance"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  ingress {
    description = "To-Do API"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "todo-api-sg"
  }
}

resource "aws_instance" "todo_api" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.todo_api_sg.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1          # containers can't reach the metadata service
  }

  # Installs Docker and the Compose plugin on first boot, so the CI
  # deploy job can SSH in and immediately run `docker compose` commands.
  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user

    # Pinned Compose release, verified against its published checksum.
    mkdir -p /usr/libexec/docker/cli-plugins
    cd /tmp
    curl -fSL https://github.com/docker/compose/releases/download/${var.docker_compose_version}/docker-compose-linux-x86_64 \
      -o docker-compose-linux-x86_64
    curl -fSL https://github.com/docker/compose/releases/download/${var.docker_compose_version}/docker-compose-linux-x86_64.sha256 \
      -o docker-compose-linux-x86_64.sha256
    sha256sum -c docker-compose-linux-x86_64.sha256
    install -m 0755 docker-compose-linux-x86_64 /usr/libexec/docker/cli-plugins/docker-compose

    # Both compose files declare this network as external.
    docker network create todo-net || true

    mkdir -p /home/ec2-user/todo-api
    chown ec2-user:ec2-user /home/ec2-user/todo-api
  EOF

  # The Postgres data lives on this instance's root disk. Never let Terraform
  # replace it because of a newer AMI or an edited user_data, and refuse to
  # destroy it without an explicit edit of this block.
  lifecycle {
    ignore_changes  = [ami, user_data]
    prevent_destroy = true
  }

  tags = {
    Name = "todo-api-server"
  }
}

# Stable public IP: an auto-assigned one changes on every stop/start, which
# silently breaks the EC2_HOST secret. After the first apply, update EC2_HOST.
resource "aws_eip" "todo_api" {
  instance = aws_instance.todo_api.id
  domain   = "vpc"

  tags = {
    Name = "todo-api-eip"
  }
}

output "instance_public_ip" {
  description = "Public (Elastic) IP address of the EC2 instance"
  value       = aws_eip.todo_api.public_ip
}
