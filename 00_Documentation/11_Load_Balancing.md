# Manual HAProxy Configuration

## Overview

This guide configures two HAProxy instances on Alpine Linux, one in EAST and one in WEST. Each instance provides an HTTP entry point for the existing web workers, a PostgreSQL connection endpoint that follows the Patroni primary, and an S3 endpoint for the Garage cluster.

The procedure covers HAProxy installation, its complete configuration files, service startup, statistics and the captured checks. Web application deployment, NGINX configuration, DNS configuration and certificate issuance are separate tasks. The configuration shown here uses HTTP; HTTPS is not part of this procedure.

## Infrastructure and listening ports

| Component | EAST | WEST | CLOUD |
|---|---|---|---|
| HAProxy | `192.168.72.2` | `192.168.73.2` | — |
| Existing web worker | `192.168.72.3:80` | `192.168.73.3:80` | — |
| PostgreSQL | `192.168.72.4:5432` | `192.168.73.4:5432` | — |
| Patroni REST API | `192.168.72.4:8008` | `192.168.73.4:8008` | — |
| Garage S3 API | `192.168.72.5:3900` | `192.168.73.5:3900` | `192.168.74.6:3900` |
| Garage health API | `192.168.72.5:3903` | `192.168.73.5:3903` | `192.168.74.6:3903` |

| HAProxy port | Purpose |
|---|---|
| `80/TCP` | HTTP frontend for the existing web workers |
| `5000/TCP` | PostgreSQL connections to the current primary |
| `3900/TCP` | Garage S3 connections |
| `8404/TCP` | Password-protected statistics at `/stats` |

Routing between all three LANs and the existing firewall rules must already allow these flows. Both HAProxy nodes need access to both web workers, both PostgreSQL and Patroni endpoints, and all three Garage endpoints. Limit data ports to their intended clients and the statistics port to administration and monitoring sources.

## 1. Install HAProxy on both nodes

The remaining installation and configuration commands use `sudo`. When already using a root shell, omit `sudo`.

```bash
sudo apk update
```

```bash
sudo apk add haproxy haproxy-openrc curl iproute2 postgresql-client openssl busybox-openrc
```

<img width="1967" height="755" alt="image" src="https://github.com/user-attachments/assets/2649767a-df67-4ae3-ba25-a85c4ca79c59" />


*Screenshot 01. Package installation on both load balancers.*

```bash
haproxy -v
```

<img width="1967" height="755" alt="image" src="https://github.com/user-attachments/assets/9dac8e40-c42b-4c9a-b6d8-f5af6c0de4d6" />


*Screenshot 02. Installed packages and HAProxy version on EAST and WEST.*

Enable the local syslog service used by the HAProxy configuration:

```bash
sudo rc-update add syslog boot
```

```bash
sudo rc-service syslog start
```

## 2. Check the existing upstream endpoints

Run the following commands from each HAProxy node. These checks confirm upstream connectivity before configuring the proxy; they do not install or change the upstream services.

```bash
curl -sS --connect-timeout 3 --max-time 5 -i http://192.168.72.3/health/live
```

```bash
curl -sS --connect-timeout 3 --max-time 5 -i http://192.168.73.3/health/live
```

The liveness endpoint should return HTTP `200`. It checks the application process without requiring its database and S3 dependencies to be ready.

<img width="1080" height="841" alt="image" src="https://github.com/user-attachments/assets/f05dfd03-0f27-4396-a682-67d32f48b6cd" />


*Screenshot 03. Direct liveness checks of both web nodes.*

Check which PostgreSQL node is currently eligible for writes:

```bash
curl -sS --connect-timeout 3 --max-time 5 -o /dev/null -w 'east-db: HTTP %{http_code}\n' http://192.168.72.4:8008/primary
```

```bash
curl -sS --connect-timeout 3 --max-time 5 -o /dev/null -w 'west-db: HTTP %{http_code}\n' http://192.168.73.4:8008/primary
```

In the captured state, EAST returns `200` and WEST returns `503`. The latter is expected for a replica on `/primary`. These roles can change later: the configuration must follow the API result rather than assume that EAST is always primary.

<img width="1207" height="723" alt="image" src="https://github.com/user-attachments/assets/55f9449e-2547-4b70-bf53-63ce9213eb2d" />

*Screenshot 04. Patroni primary checks return 200 for EAST and 503 for WEST.*

## 3. Configure EAST

On **east-load-balancer**, back up the existing configuration if present:

```bash
sudo sh -c 'test ! -f /etc/haproxy/haproxy.cfg || cp -a /etc/haproxy/haproxy.cfg "/etc/haproxy/haproxy.cfg.bak.$(date +%Y%m%d-%H%M%S)"'
```

```bash
sudo vi /etc/haproxy/haproxy.cfg
```

Replace the entire file with the following configuration. Set a real statistics password in place of `CHANGE_THIS_PASSWORD`; keep the public documentation and screenshots free of that password.

```haproxy
global
    log /dev/log local0
    log /dev/log local1 notice
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    log global
    option dontlognull
    timeout connect 5s
    timeout client 60s
    timeout server 60s
    timeout check 5s

frontend shop_http
    bind *:80
    mode http
    option httplog
    option forwardfor
    http-request set-header X-Forwarded-Proto http
    default_backend shop_web

backend shop_web
    mode http
    option httpchk GET /health
    http-check expect status 200
    server nginx_east 192.168.72.3:80 check inter 3s fall 3 rise 2
    server nginx_west 192.168.73.3:80 check inter 3s fall 3 rise 2 backup

frontend postgres
    bind *:5000
    mode tcp
    option tcplog
    timeout client 5m
    default_backend postgres_primary

backend postgres_primary
    mode tcp
    timeout server 5m
    option httpchk GET /primary
    http-check expect status 200
    default-server inter 2s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg_east 192.168.72.4:5432 check port 8008
    server pg_west 192.168.73.4:5432 check port 8008

frontend garage_s3
    bind *:3900
    mode tcp
    option tcplog
    timeout client 5m
    default_backend garage_s3_nodes

backend garage_s3_nodes
    mode tcp
    timeout server 5m
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    option allbackups
    server garage_east 192.168.72.5:3900 check port 3903 inter 3s fall 3 rise 2
    server garage_cloud 192.168.74.6:3900 check port 3903 inter 3s fall 3 rise 2 backup
    server garage_west 192.168.73.5:3900 check port 3903 inter 3s fall 3 rise 2 backup

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 5s
    stats auth haproxyadmin:CHANGE_THIS_PASSWORD
```

## 4. Configure WEST

On **west-load-balancer**, back up and edit the same path:

```bash
sudo sh -c 'test ! -f /etc/haproxy/haproxy.cfg || cp -a /etc/haproxy/haproxy.cfg "/etc/haproxy/haproxy.cfg.bak.$(date +%Y%m%d-%H%M%S)"'
```

```bash
sudo vi /etc/haproxy/haproxy.cfg
```

Replace the entire file with this complete WEST configuration:

```haproxy
global
    log /dev/log local0
    log /dev/log local1 notice
    maxconn 4096
    user haproxy
    group haproxy
    daemon

defaults
    log global
    option dontlognull
    timeout connect 5s
    timeout client 60s
    timeout server 60s
    timeout check 5s

frontend shop_http
    bind *:80
    mode http
    option httplog
    option forwardfor
    http-request set-header X-Forwarded-Proto http
    default_backend shop_web

backend shop_web
    mode http
    option httpchk GET /health
    http-check expect status 200
    server nginx_west 192.168.73.3:80 check inter 3s fall 3 rise 2
    server nginx_east 192.168.72.3:80 check inter 3s fall 3 rise 2 backup

frontend postgres
    bind *:5000
    mode tcp
    option tcplog
    timeout client 5m
    default_backend postgres_primary

backend postgres_primary
    mode tcp
    timeout server 5m
    option httpchk GET /primary
    http-check expect status 200
    default-server inter 2s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg_east 192.168.72.4:5432 check port 8008
    server pg_west 192.168.73.4:5432 check port 8008

frontend garage_s3
    bind *:3900
    mode tcp
    option tcplog
    timeout client 5m
    default_backend garage_s3_nodes

backend garage_s3_nodes
    mode tcp
    timeout server 5m
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    option allbackups
    server garage_west 192.168.73.5:3900 check port 3903 inter 3s fall 3 rise 2
    server garage_cloud 192.168.74.6:3900 check port 3903 inter 3s fall 3 rise 2 backup
    server garage_east 192.168.72.5:3900 check port 3903 inter 3s fall 3 rise 2 backup

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 5s
    stats auth haproxyadmin:CHANGE_THIS_PASSWORD
```

<img width="1494" height="1399" alt="image" src="https://github.com/user-attachments/assets/7df04c43-6f96-4ff0-888a-f17169f0f1bb" />


*Screenshot 05. Editing the EAST and WEST configurations.*

The editing screenshot records an intermediate state. Its EAST window contains a mistyped `global` heading; the complete configuration above has the corrected heading. The syntax validation below shows the errors being corrected.

### How the configuration selects upstream nodes

| Backend | Selection logic |
|---|---|
| `shop_web` | Prefer the local web worker and use the other worker as `backup`. Require HTTP `200` from `/health`. |
| `postgres_primary` | Forward TCP connections to port `5432`; check `/primary` on Patroni port `8008`. Only the current primary should return `200`. |
| `garage_s3_nodes` | Prefer local Garage; check `/health` on port `3903`. If the local node is unavailable, distribute new connections between the healthy backup nodes. |

`option allbackups` means CLOUD and the remote branch share backup traffic. It does not establish a CLOUD-first order. HAProxy selects a Garage API endpoint; Garage itself controls replication and quorum.

`timeout client` and `timeout server` are inactivity timeouts. PostgreSQL and S3 use five minutes here, while the HTTP defaults remain 60 seconds. `fall 3` requires three failed checks before marking a node down; `rise 2` requires two successful checks before restoring it. Detection time also depends on check intervals and timeouts.

`on-marked-down shutdown-sessions` closes database sessions to an upstream that no longer qualifies as primary. Applications must reconnect; an interrupted transaction is not migrated to the new primary.

## 5. Set permissions and validate the configuration

Run on **both HAProxy nodes**:

```bash
sudo chown root:root /etc/haproxy/haproxy.cfg
```

```bash
sudo chmod 640 /etc/haproxy/haproxy.cfg
```

<img width="886" height="247" alt="image" src="https://github.com/user-attachments/assets/388570a3-122d-4fb6-a956-7850c2087662" />


*Screenshot 06. Setting configuration ownership with sudo.*

The first unprivileged `chown` attempt in the screenshot is rejected. Running it through `sudo` succeeds.

```bash
sudo haproxy -c -V -f /etc/haproxy/haproxy.cfg
```

The final result must be:

```text
Configuration file is valid
```

<img width="886" height="475" alt="image" src="https://github.com/user-attachments/assets/d1b280fc-533d-4c97-a975-04889850eae9" />


*Screenshot 07. Correcting typing errors and validating both configuration files.*

This screenshot includes earlier typing errors and the successful final validations on both nodes. Correct all errors before starting or reloading HAProxy. A successful syntax check does not by itself prove that upstream services are ready.

## 6. Enable and start HAProxy

On both nodes:

```bash
sudo rc-update add haproxy default
```

For the first start:

```bash
sudo rc-service haproxy start
```

After subsequent configuration changes, validate and reload:

```bash
sudo haproxy -c -V -f /etc/haproxy/haproxy.cfg && sudo rc-service haproxy reload
```

```bash
sudo rc-service haproxy status
```

## 7. Inspect the statistics pages

Open the HAProxy statistics pages from an allowed administration client:

- EAST: [http://192.168.72.2:8404/stats](http://192.168.72.2:8404/stats)
- WEST: [http://192.168.73.2:8404/stats](http://192.168.73.2:8404/stats)

For these manual configurations, the username is `haproxyadmin` and the password is the value entered in `stats auth`.

### Intermediate state during setup

<img width="2048" height="1018" alt="image" src="https://github.com/user-attachments/assets/900bd17b-2441-4e04-8064-e0440e02f142" />

*Screenshot 08. EAST statistics during setup with web readiness checks returning 503.*

<img width="2048" height="1018" alt="image" src="https://github.com/user-attachments/assets/65dea79d-037e-4e42-af99-95b53671fb89" />


*Screenshot 09. WEST statistics during setup with web readiness checks returning 503.*

Both initial captures show `503` from the web readiness checks. PostgreSQL primary selection and Garage checks are already working, but the web backend is not ready at that point. This is not the final healthy state. The screenshots do not establish the exact cause of the earlier web readiness failures.

### Working state

<img width="2031" height="1023" alt="image" src="https://github.com/user-attachments/assets/9973f540-9982-401e-9126-ce5e32c20ed6" />


*Screenshot 10. Healthy WEST configuration with both web nodes and all Garage nodes available.*

In the WEST capture, `nginx_west` is the active web server and `nginx_east` is an available backup. `pg_east` is eligible for the write backend, while `pg_west` returns `503` because it is a replica. Garage has a local active node and two healthy backups.

A red PostgreSQL replica row in `postgres_primary` does not necessarily indicate a database failure. This backend deliberately excludes replicas from write connections.

## 8. Observe a web-node failure

The captured test pauses the existing **east-web** VM in Virtual Machine Manager. HAProxy remains running. This simulates an unresponsive upstream rather than a configuration change to the website.

<img width="2031" height="1023" alt="image" src="https://github.com/user-attachments/assets/ff99a6a6-a522-4d08-b336-78b8b4a193de" />


*Screenshot 11. Pausing the east-web VM in Virtual Machine Manager.*

The first failed check does not immediately mark the server down because `fall 3` is configured:

<img width="2031" height="1023" alt="image" src="https://github.com/user-attachments/assets/e520757d-f86d-4675-982d-c1cfe3000b01" />


*Screenshot 12. First east-web health-check timeout before the DOWN threshold.*

After the failure threshold is reached, `nginx_east` is marked `DOWN` and the healthy `nginx_west` backup becomes eligible for traffic:

<img width="2031" height="1023" alt="image" src="https://github.com/user-attachments/assets/ee946264-f9d6-4f10-b2e4-49c6707c8d18" />


*Screenshot 13. east-web is DOWN while the WEST backup remains available.*

Resume `east-web` after the test. With `rise 2`, it becomes eligible again after two successful checks. The provided captures show failure detection and backup availability; they do not by themselves establish that a new client request completed during the paused interval.

## 9. Confirm application readiness through the local frontend

On a HAProxy node:

```bash
curl -sS --max-time 15 -i http://127.0.0.1/health
```

<img width="538" height="174" alt="image" src="https://github.com/user-attachments/assets/5404ac35-45a9-4069-8275-9067ef906f94" />


*Screenshot 14. Local health response confirms database and Garage readiness.*

The captured response is HTTP `200` with `database: ok`, `garage: ok` and `status: ok`. This confirms that the health request completed successfully at the time of capture. The application performs a database query and a signed bucket-access check; this is not a complete object read/write or database failover test.

## Operational notes

- Existing web applications use their local HAProxy for PostgreSQL and S3. Loss of that HAProxy can make the corresponding web worker unready, even if its NGINX process is still running.
- HAProxy does not elect a PostgreSQL primary or replicate S3 data. Patroni and Garage own those operations.
- The evidence here covers configuration validation, statistics, web-node failure detection and a successful health response. It does not claim completed PostgreSQL, Garage or physical-host failover tests.
- Three logical zones on two physical hosts are not three independent failure domains. In the reviewed Terraform placement, losing `host_1` also removes EAST and CLOUD, including two etcd and two Garage members.
- The automated HAProxy role may overwrite manual changes when rerun. Review its template and variables before returning to automated management.

## References

- [HAProxy configuration manual](https://docs.haproxy.org/3.4/configuration.html)
- [Patroni REST API health checks](https://patroni.readthedocs.io/en/latest/rest_api.html)
- [Garage administration API health endpoint](https://garagehq.deuxfleurs.fr/documentation/reference-manual/admin-api/)

