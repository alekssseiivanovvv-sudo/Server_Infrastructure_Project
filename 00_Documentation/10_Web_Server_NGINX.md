# NGINX Web Server and Reverse Proxy

## Overview

NGINX is the front door of each web worker. It runs in the `nginx-web` container, serves the static storefront and forwards API, health and image requests to the Flask backend.

```text
Client ──► HAProxy (443/80) ──► NGINX :80 ──┬─► /            static files (index.html)
                                            ├─► /api/        ──► backend:5000
                                            ├─► /health      ──► backend:5000/health
                                            └─► /images/     ──► backend:5000/api/image/
```

| Component | Value |
|---|---|
| Image | `nginx:alpine` |
| Container | `nginx-web` |
| Listening port | `80` |
| Static root | `/usr/share/nginx/html` (mounted read-only from `/opt/shop-web/html`) |
| Upstream | `backend:5000` (Compose service name) |

### Design decisions

- **Static files from NGINX, dynamic from Flask.** NGINX serves HTML much more efficiently than gunicorn.
- **Single-page fallback.** Unknown paths return `index.html`.
- **Readiness through NGINX.** `/health` is proxied to the backend, so HAProxy's check reflects the real state of the database and S3 and not just whether NGINX is running.
- **Image proxying.** Product images are not public. Browsers request `/images/<key>`, NGINX rewrites it to `/api/image/<key>` and the backend fetches the object from Garage.
- **TLS is not terminated here.** HTTPS ends on HAProxy, and traffic to NGINX uses the internal network.

## Prerequisites

- Docker and Compose installed (see [08_Docker.md](08_Docker.md)).
- The backend container defined in the same Compose project.

## 1. Create the Dockerfile

`/opt/shop-web/nginx/Dockerfile`:

```dockerfile
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
```

The image replaces the default configuration with the project file.

## 2. Create the NGINX configuration

`/opt/shop-web/nginx/nginx.conf`:

```nginx
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    upstream backend_servers {
        server backend:5000;
    }

    server {
        listen 80;
        server_name _;

        root /usr/share/nginx/html;
        index index.html;

        location /health {
            proxy_pass http://backend_servers/health;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        location /api/ {
            proxy_pass http://backend_servers;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        location /images/ {
            proxy_pass http://backend_servers/api/image/;
            proxy_set_header Host $host;
        }

        location / {
            try_files $uri $uri/ /index.html;
        }
    }
}
```

| Location | Behaviour |
|---|---|
| `/health` | Readiness check, proxied to the backend |
| `/api/` | Product list, product creation and purchase endpoints |
| `/images/` | Rewritten to `/api/image/` and streamed from Garage |
| `/` | Static files with `index.html` fallback |

The `X-Real-IP` and `X-Forwarded-For` headers preserve the client address. Behind HAProxy this is the load balancer address unless HAProxy forwards the original client IP.

## 3. Add the static storefront

Place the storefront at `/opt/shop-web/html/index.html`. Because the directory is a read-only bind mount, changes appear immediately without rebuilding the image.

## 4. Test the configuration

Syntax test inside the running container:

```sh
sudo docker exec nginx-web nginx -t
```

Expected output:

```text
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

## 5. Build and start

```sh
cd /opt/shop-web
sudo docker compose up -d --build nginx
```

## 6. Verify

| Test | Command | Expected |
|---|---|---|
| Static page | `curl -I http://127.0.0.1/` | `200 OK` |
| Fallback | `curl -I http://127.0.0.1/unknown` | `200 OK` (returns `index.html`) |
| API | `curl -s http://127.0.0.1/api/products` | JSON array |
| Readiness | `curl -s http://127.0.0.1/health` | `{"status":"ok",...}` |
| Missing image | `curl -I http://127.0.0.1/images/none.png` | `404` |

## 7. Connection with HAProxy

HAProxy checks each NGINX node with `GET /health` every 3 seconds. A node is removed after 3 failures and returned after 2 successes. The local node is primary and the remote site's NGINX is a backup:

```text
server nginx_east 192.168.72.3:80 check inter 3s fall 3 rise 2
server nginx_west 192.168.73.3:80 check inter 3s fall 3 rise 2 backup
```

If a site loses its database connection or S3 access, `/health` returns `503` and traffic moves to the other site.

## Ansible Automation

NGINX is deployed with the web application by the `shop_web` role, which copies `files/shop-web/nginx` and the `html` directory and rebuilds the stack. Changing `nginx.conf` in Git and rerunning the playbook rebuilds the image.

```sh
cd 02_Ansible
ansible-playbook 06_WEB_HAPROXY_DNS_service.yml --ask-vault-pass --limit web_servers
```

## Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| `502 Bad Gateway` | Backend container down or still starting | `docker compose ps`, `docker logs python-backend` |
| `/health` is `503` | Database or Garage failure | `curl http://127.0.0.1/health` shows which check failed |
| Container exits at start | Invalid `nginx.conf` | `docker logs nginx-web` |
| Config change has no effect | Image not rebuilt | `docker compose up -d --build nginx` |
| Images return `404` | Wrong key or bucket | Check `GARAGE_BUCKET` and the object key |
| Old page after edit | Browser cache | Hard reload |

## Result

NGINX serves the storefront, hides the backend, exposes a single readiness endpoint to HAProxy and gives the browser access to private images through the application.
