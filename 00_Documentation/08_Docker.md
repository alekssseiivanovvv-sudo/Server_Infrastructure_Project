# Docker Container Runtime for the Shop Web Workers

[![Alpine Linux](https://img.shields.io/badge/Alpine_Linux-0D597F?style=for-the-badge&logo=alpinelinux&logoColor=white)](https://alpinelinux.org/) [![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)

## Overview

This document describes how Docker is used in the project. Docker runs only on the two Alpine web workers, `east-web` and `west-web`. Each worker runs the same two-container application stack managed by Docker Compose:

| Container | Image | Purpose |
|---|---|---|
| `nginx-web` | built from `nginx:alpine` | Serves the static storefront and proxies API requests |
| `python-backend` | built from `python:3.12-alpine` | Flask application served by gunicorn on port `5000` |

Only NGINX is published to the network (port `80`). The backend has no published port and is reachable only from NGINX through the private Compose network.

| Node | Address | Role |
|---|---:|---|
| `east-web` | `192.168.72.3` | Primary web worker for the east HAProxy |
| `west-web` | `192.168.73.3` | Primary web worker for the west HAProxy |

### Design decisions

- **Compose instead of an orchestrator.** Two identical workers behind HAProxy already provide redundancy, so Kubernetes or Swarm would add complexity without a benefit at this scale.
- **Images are built on the node.** The project has no private registry. `docker compose up --build` builds both images from the files copied by Ansible, so every worker is built from the same source in Git.
- **Secrets stay out of the image.** Database and S3 credentials are passed through a `0600` `.env` file generated from Ansible Vault.
- **Backend not published.** Compose gives each service a DNS name, so NGINX reaches the backend as `backend:5000` without exposing it on the host.
- **`restart: unless-stopped`.** Containers return automatically after a reboot or crash.

## Important Security Notes

The following values must never be committed to Git or shown in unredacted screenshots:

- `DB_PASS`
- `GARAGE_ACCESS_KEY`
- `GARAGE_SECRET_KEY`

The `.env` file lives only on the web workers in `/opt/shop-web/.env`, owned by root with mode `0600`. In this project the values come from Ansible Vault (`vault_postgres_app_password`, `vault_garage_app_access_key`, `vault_garage_app_secret_key`).

## Prerequisites

- Alpine Linux web workers reachable over the project network.
- Working local HAProxy node on the same site (PostgreSQL on port `5000`, Garage on port `3900`), because the backend reaches both services through it.
- Root or `sudo` access.

## 1. Install Docker

```sh
sudo apk update
sudo apk add docker docker-cli-compose curl
```

Enable and start the service:

```sh
sudo rc-update add docker default
sudo rc-service docker start
```

Verify:

```sh
sudo docker version
sudo docker compose version
```

## 2. Create the project directory

```sh
sudo mkdir -p /opt/shop-web
sudo chown root:root /opt/shop-web
```

Copy the application files from the repository (`02_Ansible/files/shop-web`) so the directory looks like this:

```text
/opt/shop-web
├── docker-compose.yml
├── .env
├── backend/
│   ├── Dockerfile
│   ├── app.py
│   └── requirements.txt
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf
└── html/
    └── index.html
```

## 3. Create the environment file

The backend reads all of its connection settings from environment variables. Use the HAProxy node on the same site as the host:

| Site | `DB_HOST` / S3 host |
|---|---|
| East | `192.168.72.2` |
| West | `192.168.73.2` |

```sh
sudo nano /opt/shop-web/.env
```

```ini
DB_HOST=192.168.72.2
DB_PORT=5000
DB_NAME=shopdb
DB_USER=appuser
DB_PASS=<DATABASE_PASSWORD>

GARAGE_ENDPOINT=http://192.168.72.2:3900
GARAGE_ACCESS_KEY=<GARAGE_ACCESS_KEY>
GARAGE_SECRET_KEY=<GARAGE_SECRET_KEY>
GARAGE_BUCKET=product-images
GARAGE_REGION=garage
```

Restrict access:

```sh
sudo chmod 600 /opt/shop-web/.env
```

## 4. Review the Compose file

```yaml
services:
  backend:
    build: ./backend
    container_name: python-backend
    env_file:
      - .env
    restart: unless-stopped

  nginx:
    build: ./nginx
    container_name: nginx-web
    ports:
      - "80:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
    depends_on:
      - backend
    restart: unless-stopped
```

- `env_file` injects the credentials into the backend only.
- The `html` directory is mounted read-only, so the storefront can be updated without rebuilding the image.
- `depends_on` starts the backend before NGINX.

Validate the syntax:

```sh
cd /opt/shop-web
sudo docker compose config --quiet
```

## 5. Build and start the stack

```sh
cd /opt/shop-web
sudo docker compose up -d --build --remove-orphans
```

Check the result:

```sh
sudo docker compose ps
```

Both containers should be `running`.

## 6. Verify the application

Liveness only proves that the Flask process is running:

```sh
curl -s http://127.0.0.1/health/live
```

Readiness checks the database and Garage through the HAProxy node:

```sh
curl -s http://127.0.0.1/health
```

A healthy response:

```json
{"checks":{"database":"ok","garage":"ok"},"status":"ok"}
```

## 7. Firewall interaction

Docker publishes port `80` through its own NAT rules, so traffic to the container is forwarded and does not pass the `input` chain. The host firewall therefore restricts it in the `forward` chain:

```nft
chain forward {
  type filter hook forward priority -10; policy accept;
  ip saddr { 192.168.72.2, 192.168.73.2 } tcp dport 80 accept
  tcp dport 80 drop
}
```

Only the two HAProxy nodes may reach the web containers.

## Ansible Automation

This procedure is automated by the `shop_web` role in `06_WEB_HAPROXY_DNS_service.yml`.

| Step | Ansible action |
|---|---|
| Safety check | Asserts that the host runs Alpine |
| Proxy selection | Uses the HAProxy node of the same site |
| Packages | Installs `docker`, `docker-cli-compose`, `curl` |
| Service | Enables and starts Docker |
| Files | Copies `files/shop-web` to `/opt/shop-web` |
| Secrets | Templates `.env` with mode `0600` and `no_log` |
| Validation | `docker compose config --quiet` |
| Deployment | `docker compose up -d --build --remove-orphans` |
| Verification | Waits for port 80 and checks `/health/live` |

Run it:

```sh
cd 02_Ansible
ansible-playbook 06_WEB_HAPROXY_DNS_service.yml --ask-vault-pass --limit web_servers
```

## Container Monitoring

Both workers are monitored by Grafana Alloy with the built-in cAdvisor exporter. Because Docker 29 uses the containerd image store, Alloy needs the containerd socket (`/run/docker/containerd/containerd.sock`, namespace `moby`) and must run as root. See [12_Monitoring_Stack.md](12_Monitoring_Stack.md).

## Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| `docker compose` not found | Compose plugin missing | `apk add docker-cli-compose` |
| Backend restarts repeatedly | Wrong `.env` or unreachable database | `docker logs python-backend` |
| `/health` returns 503 with `database: failed` | Local HAProxy or Patroni primary unavailable | `nc -zv <haproxy> 5000` |
| `/health` returns 503 with `garage: failed` | Wrong key, bucket missing, or S3 proxy down | `docker logs python-backend`, check Garage doc |
| Build fails on `psycopg2` | Build packages missing in image | Check `apk add` line in `backend/Dockerfile` |
| Site reachable directly but not through HAProxy | `forward` chain drops the proxy | `sudo nft list ruleset` |
| Port 80 in use | Another service bound to it | `sudo ss -ltnp \| grep :80` |

## Updating or Removing

Apply a code change:

```sh
cd /opt/shop-web
sudo docker compose up -d --build
```

Stop the stack:

```sh
sudo docker compose down
```

Remove unused images afterwards:

```sh
sudo docker image prune -f
```

## Result

Each web worker runs an identical NGINX and Flask stack under Docker Compose. Credentials stay out of Git and images, only HAProxy can reach the published port, and the whole deployment is repeatable through Ansible.
