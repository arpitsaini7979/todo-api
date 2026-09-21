# To-Do API

![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)
![Flask](https://img.shields.io/badge/Flask-3.0-000000?logo=flask&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-844FBA?logo=terraform&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?logo=githubactions&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)

A small To-Do API that I built to learn DevOps properly, by doing every step myself instead of
only watching tutorials.

The app is boring on purpose (Flask and Postgres). The interesting part is everything around
it: Docker, Terraform, GitHub Actions, Prometheus and Grafana, and a Kubernetes lab with
ArgoCD and autoscaling.

I don't keep the AWS server running because it costs money, so there is no live link. The
whole setup is in code, and I can bring it back with a few commands (see
[Putting it on AWS](#putting-it-on-aws)).

## The big picture

```mermaid
flowchart LR
    dev([me<br/>git push]) --> gh["GitHub Actions<br/>1. run tests<br/>2. build image<br/>3. deploy"]

    gh -- "push image" --> hub[(Docker Hub)]
    gh -- "SSH: start new version" --> api
    hub -- "pull image" --> api

    subgraph AWS["AWS EC2, made by Terraform"]
        api["todo-api<br/>Flask + Gunicorn"] --> db[(PostgreSQL)]
        api -- "/metrics" --> prom[Prometheus]
        node[node-exporter] --> prom
        prom --> graf[Grafana]
    end

    tf[Terraform] -. creates .-> AWS
    tf -. keeps state in .-> s3[(S3 bucket)]
```

When I push to `main`, GitHub Actions runs the tests, builds a Docker image, pushes it to
Docker Hub, and then logs in to the server over SSH and starts the new version. Terraform
created that server, and it remembers what it built in an S3 bucket. Prometheus and Grafana
run next to the app, so I can see CPU, memory and uptime.

Two choices I made on purpose. Only ports 22 and 3000 are open to the internet. Prometheus and
Grafana only listen on localhost, so I get to them through an SSH tunnel.

## The Kubernetes part

The Kubernetes side is a separate, temporary lab. I didn't want to experiment on the same
server that runs the app (more on that in [Things that went wrong](#things-that-went-wrong)).

```mermaid
flowchart TB
    git[(GitHub<br/>k8s/ folder)] -- "ArgoCD checks about every 3 min" --> argo[ArgoCD]

    subgraph cluster["k3s cluster, one node"]
        argo -- applies --> dep[Deployment<br/>todo-api]
        hpa[HPA<br/>2 to 4 pods] -- "sets the replica count" --> dep
        dep --> pods[todo-api pods]
        svc[Service<br/>NodePort 30080] --> pods
        pods -- "DATABASE_URL from a Secret" --> dbsvc[Service<br/>todo-db]
        dbsvc --> sts[(StatefulSet<br/>Postgres + 2Gi volume)]
    end

    user([browser or curl]) --> svc
```

## What's in the repo

```
app.py, tests/            the API and its unit tests
Dockerfile                multi-stage image, non-root user, healthcheck
docker-compose.yml        local development (API + Postgres)
docker-compose.prod.yml   what runs on the server (pulls the image CI built)
monitoring/               Prometheus config, Grafana dashboard, compose file
terraform/                the AWS server (EC2, security group, Elastic IP, S3 backend)
terraform/k8s-lab/        a temporary single-node k3s server
k8s/                      Deployment, Service, Postgres StatefulSet, HPA
argocd/                   the ArgoCD Application
.github/workflows/ci.yml  test, build and push, deploy
```

## The API

| Method | Endpoint | What it does |
|---|---|---|
| GET | `/health` | Is the app alive |
| GET | `/metrics` | Prometheus metrics |
| GET | `/todos` | List all to-dos |
| POST | `/todos` | Create one (`title` is a non-empty string, up to 200 characters) |
| GET | `/todos/<id>` | Get one, 404 if it doesn't exist |
| PUT | `/todos/<id>` | Change `title` and/or `done` (`done` has to be a boolean) |
| DELETE | `/todos/<id>` | Delete one |

If you set an `API_KEY` environment variable, `/todos` needs an `X-API-Key` header. `/health`
and `/metrics` stay open so the probes and Prometheus keep working.

## Run it on your machine

```bash
docker compose up --build            # API on http://localhost:3000
pip install -r requirements-dev.txt
python -m pytest                     # unit tests, they use SQLite so no Postgres needed
```

The compose file here has a throwaway database password. On the server the password comes
from a GitHub secret.

## Putting it on AWS

You need an AWS account, an IAM user that can use EC2 and S3, the AWS CLI, and Terraform 1.10
or newer.

1. **Make the state bucket by hand, once.** Terraform can't create the bucket that stores its
   own state. Create an S3 bucket with a unique name, turn versioning on, and put the name in
   `terraform/backend.tf`.
2. **Create an EC2 key pair** and keep the `.pem` file somewhere safe.
3. **Create the server.**

   ```bash
   cd terraform
   terraform init
   terraform apply -var="key_pair_name=<your-key-pair>"   # prints instance_public_ip
   ```

4. **Add the GitHub secrets** (Settings, Secrets and variables, Actions). The table is in the
   next section.
5. **Merge to `main`.** CI tests, builds and deploys.
6. **Start monitoring, once, on the server.** CI copies the `monitoring/` folder over, but it
   only manages the stack after `monitoring/.env` exists:

   ```bash
   ssh -i <key>.pem ec2-user@<ip>
   cd ~/todo-api/monitoring
   cp .env.example .env && chmod 600 .env    # fill in 3 image versions and a Grafana password
   docker compose -f docker-compose.monitoring.yml up -d
   ```

   Then from your own machine:

   ```bash
   ssh -i <key>.pem -L 3001:localhost:3001 -L 9090:localhost:9090 ec2-user@<ip>
   # Grafana:    http://localhost:3001/d/todo-api-overview
   # Prometheus: http://localhost:9090/targets
   ```

The instance has `prevent_destroy` on, because the database lives on its disk. To tear it
down, set that to `false` first and then run `terraform destroy`.

## CI/CD

Pull requests only run the tests. A push to `main` runs the whole thing:

1. Run the tests.
2. Build the image and push it to Docker Hub, tagged with the commit SHA.
3. Copy the compose files to the server, write a `.env`, pull that exact tag, start it, and
   wait up to a minute for `/health`. If it never gets healthy, the script switches back to
   the previous tag.

Deploys don't overlap, and the third-party actions are pinned to commit SHAs.

| Secret | What goes in it |
|---|---|
| `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` | Docker Hub user, and an access token with Read and Write |
| `EC2_HOST` | The `instance_public_ip` from Terraform |
| `EC2_USER` | `ec2-user` |
| `EC2_SSH_KEY` | The whole `.pem` file |
| `POSTGRES_PASSWORD` | Letters and numbers only. Postgres reads it once, when it creates the database |
| `API_KEY` (optional) | Turns on the `X-API-Key` check |
| `EC2_HOST_FINGERPRINT` (optional) | SHA256 fingerprint of the server's SSH host key |

## The Kubernetes lab

`terraform/k8s-lab` creates one `c7i-flex.large` that runs k3s. SSH and the NodePort are only
open to your own IP.

```bash
cd terraform/k8s-lab
# terraform.tfvars is git-ignored: key_pair_name = "...", ssh_cidr_blocks = ["<your-ip>/32"]
terraform init && terraform apply
scp -i <key>.pem -r ../../k8s ec2-user@<ip>:~/
ssh -i <key>.pem ec2-user@<ip>
```

Then on the server:

```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
PW=$(openssl rand -hex 16)
kubectl create secret generic todo-db-auth --from-literal=POSTGRES_PASSWORD="$PW"
kubectl create secret generic todo-api-db  --from-literal=DATABASE_URL="postgresql://todo_user:${PW}@todo-db:5432/todo_db"
kubectl apply -f ~/k8s/
```

What I tried on it:

- **Self-healing.** Delete a pod and the ReplicaSet makes a new one.
- **GitOps.** Install ArgoCD, set `targetRevision` in `argocd/application.yaml` to your branch,
  and apply it. When I push a change to `k8s/`, ArgoCD applies it. If I edit something by hand
  with `kubectl`, ArgoCD puts it back.
- **Autoscaling.** `k8s/hpa.yaml` scales between 2 and 4 pods at 50% CPU. It only works if the
  container has `resources.requests`, and if the Deployment doesn't set `replicas` itself.

The lab costs money while it runs, so run `terraform destroy` when you're done.

## How I tested it

I ran the unit tests locally and on GitHub Actions (10 tests). I started the Docker stack and
called every endpoint, including bad input, and checked that the data survives a restart. I
started Prometheus and Grafana against it and checked that both targets were up and that all
three dashboard queries return data.

After CI deployed to a fresh server, I ran the same checks from the internet, and restarted
the API and the database to make sure nothing was lost. On the Kubernetes lab I killed pods,
watched ArgoCD apply a change from Git, and pushed load until the HPA went from 2 to 4 pods
(CPU hit 380% against a 50% target).

Things I did **not** test: the rollback part of the deploy script, the optional `API_KEY` and
host fingerprint settings on a real server, and CI syncing the monitoring stack (I started
that by hand the first time).

## Things that went wrong

Leaving these in, because I learned the most from them.

- **A token in a chat.** I pasted a Docker Hub access token into a chat window. I revoked it
  and made a new one. Secrets only go in GitHub secrets.
- **minikube on a 1 GB server.** It wants 2 CPUs and about 2 GB, and I tried it on the same
  box that was running the app. The server got so slow that even SSH stopped answering. Now I
  do experiments on a separate, temporary machine.
- **The disk was 2 GB.** After I moved to a new AWS account, the first deploy failed with
  `no space left on device`. My AMI filter (`al2023-ami-*`) also matches the minimal image,
  which has a 2 GB disk. The filter is `al2023-ami-2023.*` now, and the disk size is set to
  20 GB in the Terraform.
- **Free-plan limits.** New free-plan accounts refuse `t2.micro` and `t3.medium`. I checked the
  allowed list with `aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true`.
- **Self-healing is not autoscaling.** I mixed them up at first. The ReplicaSet keeps the
  number of pods fixed. The HPA is the thing that changes it.
- **The HPA fights `replicas`.** If the Deployment sets `replicas`, ArgoCD keeps resetting it
  and the HPA can't do its job.

## What's next

- HTTPS with a real domain
- Alerts (Alertmanager) and central logs
- Deploying over AWS SSM so SSH can be closed to the world (it's open now because the GitHub
  runners' IPs keep changing)
- Fixing a small bug: if Postgres restarts, the first request after it can return a 500,
  because the app has no `pool_pre_ping`
