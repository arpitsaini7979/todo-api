# To-Do API

## Overview
A simple To-Do list REST API built as a hands-on DevOps learning project. It covers the full
lifecycle from local development to a containerized, cloud-deployed, monitored service —
built step by step to learn Docker, Terraform, GitHub Actions, AWS, and Prometheus/Grafana.

**Status:** ✅ Deployed and live on AWS EC2, with a working CI/CD pipeline and monitoring.

## Tech Stack
- **Language/Framework:** Python 3.11 + Flask, served by Gunicorn
- **Database:** PostgreSQL 16
- **Containerization:** Docker + Docker Compose
- **Infrastructure:** Terraform (AWS EC2, t2.micro), remote state in S3
- **CI/CD:** GitHub Actions (test → build & push to Docker Hub → deploy over SSH)
- **Monitoring:** Prometheus (metrics collection) + Grafana (dashboards), node-exporter for host metrics

## Architecture
```
Developer
   |
   | git push to main
   v
GitHub Actions
   |
   |-- 1. Run pytest
   |-- 2. Build Docker image, push to Docker Hub
   |-- 3. SSH into EC2, docker compose pull + up -d
   v
AWS EC2 (Terraform-provisioned, t2.micro)
   |
   |-- Container: todo-api      (Flask + Gunicorn, port 3000, exposes /metrics)
   |-- Container: todo-db       (PostgreSQL 16)
   |-- Container: node-exporter (host CPU/memory metrics, port 9100 internal)
   |-- Container: prometheus    (scrapes todo-api + node-exporter, port 9090)
   |-- Container: grafana       (dashboards, port 3001)
   |
   (todo-api and the monitoring containers share a Docker network, "todo-net")
```

Terraform state is stored remotely in an S3 bucket (`todo-api-terraform-state-arpitsaini7979`)
with versioning enabled, instead of a local `.tfstate` file.

## API Endpoints
| Method | Endpoint       | Description             |
|--------|----------------|--------------------------|
| GET    | `/health`      | Health check             |
| GET    | `/metrics`     | Prometheus metrics       |
| GET    | `/todos`       | List all to-dos          |
| POST   | `/todos`       | Create a to-do           |
| GET    | `/todos/:id`   | Get a single to-do       |
| PUT    | `/todos/:id`   | Update a to-do           |
| DELETE | `/todos/:id`   | Delete a to-do           |

## Setup

### Prerequisites
- Python 3.11+
- Docker + Docker Compose
- Git

### Local Development
```bash
# Clone the repo
git clone https://github.com/arpitsaini7979/todo-api.git
cd todo-api

# Install dependencies
pip install -r requirements.txt

# Configure environment variables
cp .env.example .env

# Run the app (expects a local Postgres, or edit DATABASE_URL in .env)
python app.py
```

### Running with Docker Compose (app + Postgres)
```bash
docker compose up --build
```
This starts the Flask API on `http://localhost:3000` and Postgres on port 5432.

### Running tests
```bash
python -m pytest
```

### Infrastructure (Terraform)
```bash
cd terraform
terraform init
terraform plan -var="key_pair_name=<your-ec2-key-pair-name>"
terraform apply -var="key_pair_name=<your-ec2-key-pair-name>"
```
This provisions one EC2 `t2.micro` instance with a security group allowing SSH (22),
HTTP (80), the API port (3000), Grafana (3001), and Prometheus (9090), and installs
Docker + the Compose plugin on first boot.

### CI/CD
On every push to `main`, `.github/workflows/ci.yml`:
1. Runs the test suite with `pytest`.
2. Builds the Docker image and pushes it to Docker Hub (tagged `latest` and by commit SHA).
3. SSHes into the EC2 instance and runs `docker compose pull && docker compose up -d`
   using `docker-compose.prod.yml`.

Required GitHub repository secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `EC2_HOST`,
`EC2_USER`, `EC2_SSH_KEY`.

### Monitoring (Prometheus + Grafana)
One-time setup on the EC2 host (needed so the monitoring stack can reach `todo-api` by name):
```bash
docker network create todo-net
```
Then, from the `monitoring/` folder on the server:
```bash
docker compose -f docker-compose.monitoring.yml up -d
```
- Prometheus scrapes `todo-api:3000/metrics` and `node-exporter:9100` every 15s
  (config in `monitoring/prometheus.yml`).
- Grafana auto-provisions a Prometheus data source and a "To-Do API Server Overview"
  dashboard (CPU usage, memory usage, app uptime) on first startup — no manual setup needed.
- Default Grafana login is `admin` / `admin` — change it on first login.

## Live URLs
| What | URL |
|---|---|
| To-Do API | http://3.87.7.242:3000/todos |
| Health check | http://3.87.7.242:3000/health |
| Prometheus | http://3.87.7.242:9090 |
| Grafana | http://3.87.7.242:3001 |

## Project Roadmap
- [x] Phase 1: To-Do API + database
- [x] Phase 2: Dockerize
- [x] Phase 3: CI/CD with GitHub Actions
- [x] Phase 4: Terraform (AWS EC2) + Deploy
- [x] Phase 5: Monitoring with Prometheus + Grafana
