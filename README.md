# To-Do API

## Overview
A simple To-Do list REST API built as a hands-on DevOps learning project. It covers the full
lifecycle from local development to a containerized, cloud-deployed service with CI/CD and
monitoring.

**Status:** 🚧 In progress — Phase 1 (API + database)

## Tech Stack
- **Language/Framework:** <!-- e.g. Node.js + Express, or Python + Flask -->
- **Database:** <!-- e.g. PostgreSQL / SQLite -->
- **Containerization:** Docker
- **Infrastructure:** Terraform (AWS EC2)
- **CI/CD:** GitHub Actions
- **Monitoring:** Prometheus + Grafana

## Architecture
<!--
Add a short diagram or description here once later phases are built, e.g.:

  Client -> [EC2: Docker container (API)] -> [Database]
                    |
              [Prometheus] -> [Grafana]

Update this section as each phase is completed.
-->

## API Endpoints
| Method | Endpoint       | Description        |
|--------|----------------|---------------------|
| GET    | `/todos`       | List all to-dos     |
| POST   | `/todos`       | Create a to-do      |
| GET    | `/todos/:id`   | Get a single to-do  |
| PUT    | `/todos/:id`   | Update a to-do      |
| DELETE | `/todos/:id`   | Delete a to-do      |

## Setup

### Prerequisites
- <!-- e.g. Node.js 20+, or Python 3.11+ -->
- Git

### Local Development
```bash
# Clone the repo
git clone <your-repo-url>
cd todo-api

# Install dependencies
<!-- npm install    OR    pip install -r requirements.txt -->

# Configure environment variables
cp .env.example .env

# Run the app
<!-- npm start    OR    flask run -->
```

### Running with Docker
```bash
docker build -t todo-api .
docker run -p 3000:3000 todo-api
```

## Project Roadmap
- [x] Phase 1: To-Do API + database
- [ ] Phase 2: Dockerize
- [ ] Phase 3: Terraform (AWS EC2)
- [ ] Phase 4: Deploy
- [ ] Phase 5: CI/CD with GitHub Actions
- [ ] Phase 6: Monitoring with Prometheus + Grafana
