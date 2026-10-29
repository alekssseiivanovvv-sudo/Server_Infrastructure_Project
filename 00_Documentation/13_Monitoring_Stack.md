# Monitoring Stack Deployment

## Overview

This document describes the manual deployment of the central monitoring stack: metrics, logs, dashboards and alerts for every virtual machine in the project.

Everything is collected by one agent, [Grafana Alloy](https://grafana.com/docs/alloy/), installed on each machine. The agents push their data to a central monitoring server in the Cloud zone, where it is stored, displayed and checked for problems.

| Component | Runs on | Purpose |
|---|---|---|
| Grafana Alloy | Every VM (Ubuntu and Alpine) | Collects host metrics, system logs and, on Docker hosts, container metrics and logs |
| Prometheus | `cloud-monitoring` | Stores metrics on local disk |
| Loki | `cloud-monitoring` | Stores logs. Chunks and index are written to Garage S3 |
| HAProxy | `cloud-monitoring` | Local S3 proxy that chooses a healthy Garage node for Loki |
| Grafana | `cloud-monitoring` | Dashboards and alerting |
| Garage S3 | Three storage VMs | Stores Loki logs in the separate `loki-logs` bucket |
| Telegram bot | Telegram | Receives alert messages |

The monitoring server:

| Node | Zone | IP address | Purpose |
|---|---|---:|---|
| `cloud-monitoring` | Cloud | `192.168.74.3` | Prometheus, Loki, Grafana and the local Garage proxy |

### Data flow

```text
every VM
  Grafana Alloy
    |-- metrics  --->  Prometheus   192.168.74.3:9090  (local disk)
    |-- logs     --->  Loki         192.168.74.3:3100
                          |
                          v
                   HAProxy 127.0.0.1:3900   (on the monitoring VM)
                          |
         +----------------+-----------------+
         v                v                 v
     cloud-s3          east-storage     west-storage
   (primary)             (backup)         (backup)
              Garage S3 cluster, bucket loki-logs

Grafana  --reads-->  Prometheus and Loki
Grafana  --alerts->  Telegram bot
```

### Design decisions

- **Logs go to Garage, metrics stay local.** Loki can write to S3 natively. Prometheus cannot, and adding Thanos or Mimir would be disproportionate for this project. Prometheus data lives on the monitoring VM and its disk is covered by the normal backup workflow.
- **A local HAProxy sits between Loki and Garage.** Loki accepts only one S3 endpoint. HAProxy on `127.0.0.1:3900` health-checks all three Garage nodes and sends traffic to `cloud-s3` first, because it is on the same subnet. East and West are fallbacks. A failed Garage node does not stop log storage.
- **Agents push, the server does not scrape.** Alloy pushes metrics using Prometheus remote write and logs using the Loki push API. Nothing needs to be opened on the monitored machines, except the optional Alloy status port on localhost.
- **Dashboards and alerts are files.** They are provisioned from the repository. Nothing has to be clicked together in the Grafana web interface, and a rebuilt server gets the same dashboards back.

### Failure behaviour

| Failure | Result |
|---|---|
| One Garage node is lost | HAProxy sends log writes to another node. Logs continue. |
| The Cloud segment is lost | Services for clients continue working. Monitoring and alerting are unavailable until it returns. |
| The monitoring VM is lost | Metrics and the local part of the logs are lost with it. Logs already written to Garage survive on all three storage nodes. |
| An Alloy agent stops on a VM | The `Host not reporting` alert fires after 3 minutes. |

## Important Security Notes

The following values must never be committed to a public Git repository or displayed in unredacted screenshots:

- The Grafana administrator password
- The Telegram bot token
- The Garage S3 access key and secret key used by Loki
- The Prometheus administrator password hash

In this project they are stored in Ansible Vault. The files created in this guide that contain secrets (`/etc/loki/config.yml`, `/etc/grafana/grafana.ini` and the Telegram contact point) are readable only by `root` and their service group.

Prometheus and Loki accept data without authentication. Access is restricted by the host firewall (see [Firewall Rules](#27-firewall-rules)), not by the services themselves.

## Prerequisites

The following must already exist:

- The VPN and routing between the East, West and Cloud networks
- The three-node Garage cluster described in `06_S3_Cluster_Garage.md`
- An Ubuntu VM for the monitoring server with internet access to GitHub and `apt.grafana.com`
- A user with `sudo` on every machine
- The project repository cloned on the monitoring VM:

```bash
sudo apt-get install -y git
git clone https://github.com/alekssseiivanovvv-sudo/Server_Infrastructure_Project.git ~/infra
```

Values used in this guide:

| Item | Value |
|---|---|
| Prometheus version | `3.5.0` |
| Loki version | `3.5.1` |
| Prometheus system user | `prometheus_sysuser` |
| Loki system user | `loki` |
| Grafana administrator | `admin` |
| Log bucket | `loki-logs` |
| Loki S3 key name | `loki` |
| Metrics push URL | `http://192.168.74.3:9090/api/v1/write` |
| Logs push URL | `http://192.168.74.3:3100/loki/api/v1/push` |

---

# Part 1. Monitoring Server

Run these steps on `cloud-monitoring` (`192.168.74.3`).

## 1. Install Base Packages

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg unzip wget
```

---

## 2. Create the Prometheus User

The project runs Prometheus under a normal login account named `prometheus_sysuser`. Its password hash is kept in the Vault list `vault_admin_users`.

```bash
sudo useradd -m -s /bin/bash prometheus_sysuser
sudo passwd prometheus_sysuser
```

If no login is needed on this account, a system user without a shell is safer:

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin prometheus_sysuser
```

---

## 3. Create the Prometheus Directories

```bash
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown prometheus_sysuser:prometheus_sysuser /etc/prometheus /var/lib/prometheus
sudo chmod 0755 /etc/prometheus
sudo chmod 0750 /var/lib/prometheus
```

---

## 4. Install Prometheus

```bash
wget -O /tmp/prometheus-3.5.0.linux-amd64.tar.gz \
  https://github.com/prometheus/prometheus/releases/download/v3.5.0/prometheus-3.5.0.linux-amd64.tar.gz
tar -xzf /tmp/prometheus-3.5.0.linux-amd64.tar.gz -C /tmp
sudo install -o root -g root -m 0755 \
  /tmp/prometheus-3.5.0.linux-amd64/prometheus \
  /tmp/prometheus-3.5.0.linux-amd64/promtool \
  /usr/local/bin/
prometheus --version
```
<img width="799" height="127" alt="image" src="https://github.com/user-attachments/assets/cac2f1d5-2253-4cbb-bec0-2b94b07f3cbf" />

---

## 5. Configure Prometheus

```bash
sudo nano /etc/prometheus/prometheus.yml
```

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - localhost:9090
```

The host and container metrics are not scraped here. The Alloy agents push them to this server.

Set the ownership and validate the file:

```bash
sudo chown prometheus_sysuser:prometheus_sysuser /etc/prometheus/prometheus.yml
sudo chmod 0644 /etc/prometheus/prometheus.yml
promtool check config /etc/prometheus/prometheus.yml
```

The last command must end with `SUCCESS`.

<img width="799" height="69" alt="image" src="https://github.com/user-attachments/assets/d845caf8-7011-4889-ad01-4ea90cbc2d26" />

---

## 6. Create the Prometheus Service

```bash
sudo nano /etc/systemd/system/prometheus.service
```

```ini
[Unit]
Description=Prometheus monitoring server
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus_sysuser
Group=prometheus_sysuser
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.enable-lifecycle \
  --web.enable-remote-write-receiver
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

The flag `--web.enable-remote-write-receiver` allows the Alloy agents to push metrics. The flag `--web.enable-lifecycle` allows a configuration reload over HTTP.

---

# Part 2. Log Storage in Garage

## 7. Create the Log Bucket and Key in Garage

Run these commands on `cloud-s3` (`192.168.74.6`). Any Garage node would work, but `cloud-s3` is where the project runs its cluster commands.

Create a bucket used only for logs:

```bash
sudo garage bucket create loki-logs
```

Generate an access key id and a secret key. Garage requires the id to be `GK` followed by 24 hexadecimal characters and the secret to be 64 hexadecimal characters:

```bash
echo "GK$(openssl rand -hex 12)"
openssl rand -hex 32
```

Store both values in Ansible Vault as `vault_garage_loki_access_key` and `vault_garage_loki_secret_key`. Then import the key into Garage:

```bash
sudo garage key import \
  --yes \
  -n loki \
  "<GARAGE_LOKI_ACCESS_KEY>" \
  "<GARAGE_LOKI_SECRET_KEY>"
```

Grant the key read and write access to the log bucket only:

```bash
sudo garage bucket allow \
  --read \
  --write \
  loki-logs \
  --key "<GARAGE_LOKI_ACCESS_KEY>"
```

Optionally limit the bucket size, so logs can never use the space needed by product images:

```bash
sudo garage bucket set-quotas --max-size 8GiB loki-logs
```

Verify the result:

```bash
sudo garage bucket info loki-logs
```

The `loki` key must have read and write access to `loki-logs`. It must have no permissions for `product-images`.

Keeping logs in their own bucket gives them separate credentials, permissions and size limit, without giving the monitoring stack access to application images.

---

## 8. Open the S3 Port for the Monitoring Server

The Garage nodes accept the S3 port `3900` only from approved addresses. The monitoring server must be added to that list. In the project this is done by the host firewall role (the nftables rule `tcp dport 3900 accept` on the storage VMs).

By hand, on each of the three storage VMs, add the monitoring server's address to the existing allowed source list in `/etc/project-host.nft`:

```text
ip saddr { 192.168.72.2, 192.168.73.2, 192.168.74.3 } tcp dport 3900 accept
```

The two other addresses are the East and West load balancers that were already allowed. Check the file, then reload it:

```bash
sudo nft --check --file /etc/project-host.nft
sudo nft --file /etc/project-host.nft
```

Verify from the monitoring VM:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.74.6:3900/
```
<img width="799" height="69" alt="image" src="https://github.com/user-attachments/assets/c5bc35b7-9d12-4b08-b901-65930cec6c15" />


The result `403` is expected. It means the S3 API is reachable and refuses anonymous access. A timeout means the firewall still blocks the request.

---

## 9. Install the Local Garage Proxy

Run this on `cloud-monitoring`.

```bash
sudo apt-get install -y haproxy
sudo nano /etc/haproxy/haproxy.cfg
```

Replace the content with:

```haproxy
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5s
    timeout client 120s
    timeout server 120s

# Garage S3 for Loki. Only this host can reach it.
frontend garage_s3_local
    bind 127.0.0.1:3900
    default_backend garage_s3_nodes

backend garage_s3_nodes
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    option allbackups
    server cloud_s3     192.168.74.6:3900 check port 3903 inter 3s fall 3 rise 2
    server east_storage 192.168.72.5:3900 check port 3903 inter 3s fall 3 rise 2 backup
    server west_storage 192.168.73.5:3900 check port 3903 inter 3s fall 3 rise 2 backup
```

How it works:

- The listener is bound to `127.0.0.1`, so only Loki on the same machine can use it.
- Each node is checked on its admin port `3903` (`GET /health`). A node is removed after 3 failed checks and returned after 2 successful ones.
- `cloud_s3` is the primary server. The servers marked `backup` are used only when it is down.

Validate, start and verify:

```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl enable --now haproxy
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3900/
```
<img width="799" height="69" alt="image" src="https://github.com/user-attachments/assets/9b12c7a2-5fb8-4d3f-bc4c-696e46431d49" />


The last command must print `403`.

---

# Part 3. Loki

## 10. Create the Loki User and Directories

```bash
sudo useradd --system --user-group --no-create-home --shell /usr/sbin/nologin loki
sudo mkdir -p /etc/loki /var/lib/loki/chunks /var/lib/loki/rules /var/lib/loki/compactor
sudo chown loki:loki /etc/loki
sudo chown -R loki:loki /var/lib/loki
sudo chmod 0755 /etc/loki
sudo chmod -R 0750 /var/lib/loki
```

---

## 11. Install Loki

```bash
wget -O /tmp/loki-linux-amd64-3.5.1.zip \
  https://github.com/grafana/loki/releases/download/v3.5.1/loki-linux-amd64.zip
unzip -o /tmp/loki-linux-amd64-3.5.1.zip -d /tmp
sudo install -o root -g root -m 0755 /tmp/loki-linux-amd64 /usr/local/bin/loki
loki --version
```
<img width="799" height="129" alt="image" src="https://github.com/user-attachments/assets/4b4ee487-ce7d-44b2-8396-e8d8ac4f91b7" />

---

## 12. Configure Loki

```bash
sudo nano /etc/loki/config.yml
```

Replace `<GARAGE_LOKI_ACCESS_KEY>` and `<GARAGE_LOKI_SECRET_KEY>` with the values from the Vault, and `<START_DATE>` with tomorrow's date (see the note below):

```yaml
auth_enabled: false

server:
  http_listen_address: 0.0.0.0
  http_listen_port: 3100
  grpc_listen_port: 9095

common:
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-04-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
    - from: "<START_DATE>"
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  filesystem:
    directory: /var/lib/loki/chunks
  aws:
    endpoint: 127.0.0.1:3900
    region: garage
    bucketnames: loki-logs
    access_key_id: <GARAGE_LOKI_ACCESS_KEY>
    secret_access_key: <GARAGE_LOKI_SECRET_KEY>
    s3forcepathstyle: true
    insecure: true

limits_config:
  retention_period: 168h

compactor:
  working_directory: /var/lib/loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: s3

analytics:
  reporting_enabled: false
```

What the settings do:

- **Two schema entries.** The older entry keeps reading existing logs from local disk. The new entry sends everything from `<START_DATE>` onward to Garage. Never change `<START_DATE>` after the first start, because Loki uses it to find stored data. Never edit the older entry.
- **Endpoint without a scheme.** `127.0.0.1:3900` is the local HAProxy. `insecure: true` means plain HTTP on the loopback interface, and `s3forcepathstyle: true` is required by Garage.
- **Retention.** Logs are kept 168 hours (7 days). The compactor deletes expired data, and `delete_request_store: s3` tells it where deletion requests are kept.

The file contains the S3 secret, so restrict it:

```bash
sudo chown loki:loki /etc/loki/config.yml
sudo chmod 0640 /etc/loki/config.yml
sudo -u loki /usr/local/bin/loki -config.file=/etc/loki/config.yml -verify-config
```
<img width="806" height="83" alt="image" src="https://github.com/user-attachments/assets/698ad463-5d76-4ae1-846e-f2278d8c6e24" />


The last command must report that the configuration is valid.

To run without S3, remove the second schema entry and the `aws` block, and set `delete_request_store: filesystem`.

---

## 13. Create the Loki Service

```bash
sudo nano /etc/systemd/system/loki.service
```

```ini
[Unit]
Description=Loki log aggregation server
Wants=network-online.target haproxy.service
After=network-online.target haproxy.service

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/config.yml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

The service starts after HAProxy, so the S3 endpoint is already available when Loki starts.

---

# Part 4. Grafana

## 14. Install Grafana

```bash
sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
sudo chmod 0644 /etc/apt/keyrings/grafana.asc
echo 'deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main' \
  | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana
```

---

## 15. Configure the Grafana Administrator and Home Dashboard

```bash
sudo nano /etc/grafana/grafana.ini
```

In the `[security]` section set (remove the leading `;` if present):

```ini
admin_user=admin
admin_password=<GRAFANA_ADMIN_PASSWORD>
```

In the `[dashboards]` section set the home dashboard:

```ini
default_home_dashboard_path=/var/lib/grafana/dashboards/project/project-overview.json
```

Restore the ownership and permissions of the file, since it now contains a password:

```bash
sudo chown root:grafana /etc/grafana/grafana.ini
sudo chmod 0640 /etc/grafana/grafana.ini
```

---

## 16. Start the Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus loki grafana-server
systemctl is-active prometheus haproxy loki grafana-server
```
<img width="806" height="110" alt="image" src="https://github.com/user-attachments/assets/c52a21d6-f6db-41a1-810f-09eff8ca963b" />


All four lines must say `active`. If one does not, read its log, for example `sudo journalctl -u loki -n 50 --no-pager`.

The `admin_password` line only counts the first time Grafana creates its database. If Grafana has started before, set the password explicitly:

```bash
sudo grafana cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini \
  admin reset-admin-password '<GRAFANA_ADMIN_PASSWORD>'
```

On older packages the command is `grafana-cli` instead of `grafana cli`.

Verify that every service answers:

```bash
curl -s http://127.0.0.1:9090/-/ready
curl -s http://127.0.0.1:3100/ready
curl -s http://127.0.0.1:3000/api/health
```
<img width="806" height="170" alt="image" src="https://github.com/user-attachments/assets/3c9755e5-307e-483e-8d32-d2ac48b4b3f5" />


Prometheus reports that it is ready, Loki prints `ready` (this can take about 15 seconds after the start), and Grafana returns JSON with `"database": "ok"`.

---

# Part 5. Datasources and Dashboards

## 17. Create the Provisioning Folders

Grafana loads datasources and dashboards from files. Two dashboard folders are used, and they must not overlap. Grafana reads a folder recursively, so a file seen by two providers causes a duplicate-identifier error that blocks both.

| Folder on disk | Grafana folder | Content |
|---|---|---|
| `/var/lib/grafana/dashboards/ansible` | Infrastructure | Host Overview, Logs Overview, Docker Containers |
| `/var/lib/grafana/dashboards/project` | Project Monitoring | Project Overview (also the home page) |

```bash
sudo mkdir -p /etc/grafana/provisioning/datasources \
              /etc/grafana/provisioning/dashboards \
              /var/lib/grafana/dashboards/ansible \
              /var/lib/grafana/dashboards/project
sudo chown grafana:grafana /etc/grafana/provisioning/datasources \
                           /etc/grafana/provisioning/dashboards \
                           /var/lib/grafana/dashboards/ansible \
                           /var/lib/grafana/dashboards/project
```

---

## 18. Create the Datasources

The datasources have fixed identifiers, `prometheus-uid` and `loki-uid`. The dashboards and the alert rules refer to them. The `deleteDatasources` block removes any datasource with the same name that was created in the web interface, so the identifiers stay fixed.

```bash
sudo nano /etc/grafana/provisioning/datasources/ansible.yml
```

```yaml
apiVersion: 1

deleteDatasources:
  - name: Prometheus
    orgId: 1
  - name: Loki
    orgId: 1

datasources:
  - name: Prometheus
    uid: prometheus-uid
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
    version: 1
    jsonData:
      timeInterval: "15s"

  - name: Loki
    uid: loki-uid
    type: loki
    access: proxy
    url: http://localhost:3100
    editable: false
    version: 1
```

```bash
sudo chown grafana:grafana /etc/grafana/provisioning/datasources/ansible.yml
sudo chmod 0640 /etc/grafana/provisioning/datasources/ansible.yml
```
<img width="1713" height="480" alt="image" src="https://github.com/user-attachments/assets/343eed2b-56c4-45e0-b7db-5cdd858b1df5" />

---

## 19. Create the Dashboard Providers

```bash
sudo nano /etc/grafana/provisioning/dashboards/ansible.yml
```

```yaml
apiVersion: 1

providers:
  - name: 'project'
    orgId: 1
    folder: 'Project Monitoring'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards/project
      foldersFromFilesStructure: false

  - name: 'ansible'
    orgId: 1
    folder: 'Infrastructure'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: false
    options:
      path: /var/lib/grafana/dashboards/ansible
      foldersFromFilesStructure: false
```

```bash
sudo chown grafana:grafana /etc/grafana/provisioning/dashboards/ansible.yml
sudo chmod 0640 /etc/grafana/provisioning/dashboards/ansible.yml
```

The Infrastructure folder cannot be edited in the web interface (`allowUiUpdates: false`), so the files in the repository remain the single source of truth.

---

## 20. Copy the Dashboards

The dashboard files are too long to list here. They are in the repository and are copied unchanged. They must not be passed through a template engine, because the legends contain `{{ }}` placeholders that belong to Grafana.

```bash
sudo install -o grafana -g grafana -m 0644 \
  ~/infra/02_Ansible/roles/grafana_dashboards/files/dashboards/alloy-host-overview.json \
  ~/infra/02_Ansible/roles/grafana_dashboards/files/dashboards/alloy-logs-overview.json \
  ~/infra/02_Ansible/roles/grafana_dashboards/files/dashboards/alloy-docker-containers.json \
  /var/lib/grafana/dashboards/ansible/

sudo install -o grafana -g grafana -m 0644 \
  ~/infra/02_Ansible/files/grafana/dashboards/project-overview.json \
  /var/lib/grafana/dashboards/project/project-overview.json
```
<img width="1536" height="910" alt="image" src="https://github.com/user-attachments/assets/d66b494b-8c9d-4d08-9d41-32b9e0d50c45" />

<img width="1536" height="910" alt="image" src="https://github.com/user-attachments/assets/2cf86fed-0f12-436c-9216-cb1135f3a143" />

<img width="1536" height="910" alt="image" src="https://github.com/user-attachments/assets/64a02dfa-5d6d-4f18-a9d4-91f1fe506e40" />


<img width="806" height="221" alt="image" src="https://github.com/user-attachments/assets/33e47df6-ed06-432d-84fb-253b648ea37a" />


The dashboards:

| Dashboard | Data | Shows |
|---|---|---|
| Host Overview | Prometheus | Uptime, CPU, memory, disk, network and load for every host, with legends that name the host |
| Logs Overview | Loki | Error and warning counts, errors per host over time, top error sources and the latest error lines. Only real error-level lines are counted, and monitoring-stack noise is ignored |
| Docker Containers | Prometheus | CPU, memory, network and uptime of each container on the web workers |
| Project Overview | Prometheus and Loki | CPU and memory per host and the most recent logs. Used as the Grafana home page |



Grafana picks up new dashboard files within about 10 seconds. Datasource files are read only at startup, so restart Grafana once:

```bash
sudo systemctl restart grafana-server
sleep 15
sudo journalctl -u grafana-server --since '2 minutes ago' --no-pager | grep -iE 'duplicate|provisioning.*(error|fail)'
```
<img width="805" height="69" alt="image" src="https://github.com/user-attachments/assets/8415dc2e-c9c6-4440-b36f-ea534d876510" />

The last command must print nothing.

---

# Part 6. Agents

Repeat this part on every machine that is monitored. In the project these are the hosts in the inventory group `alloy_agents`: web workers, database nodes, storage nodes, load balancers, routers, the quorum node and the monitoring server itself. Alloy supports both operating systems used here: Alpine (OpenRC) and Ubuntu (systemd).

## 21. Install Alloy

**Alpine hosts:**

```bash
sudo apk update
sudo apk add alloy alloy-openrc shadow
```

The `shadow` package provides the `usermod` command used in the next step.

<img width="777" height="90" alt="image" src="https://github.com/user-attachments/assets/dffbc6e5-e3ae-4794-ad84-07119a13a6db" />


**Ubuntu hosts:**

```bash
sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
sudo chmod 0644 /etc/apt/keyrings/grafana.asc
echo 'deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main' \
  | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y alloy
```

On the monitoring VM the Grafana repository already exists from step 14, so only the last two commands are needed there.

---

## 22. Give Alloy Access to Logs and Docker

The `alloy` user must be in the groups that can read the system logs. On Docker hosts it must also be in the `docker` group.

**Alpine:**

```bash
sudo usermod -aG wheel alloy
sudo usermod -aG docker alloy     # Docker hosts only
```
<img width="777" height="71" alt="image" src="https://github.com/user-attachments/assets/c82dbadb-8f30-4f5f-ae65-af30913acc3c" />


**Ubuntu:**

```bash
sudo usermod -aG adm,systemd-journal alloy
sudo usermod -aG docker alloy     # Docker hosts only
```

A running process does not see a new group until it is restarted. Step 25 restarts Alloy.

---

## 23. Docker Hosts: Run Alloy as Root

This step applies only to the two web workers (`east-web` and `west-web`).

Alloy's built-in cAdvisor reads container details from Docker's own containerd socket, `/run/docker/containerd/containerd.sock`, and only root may use it. Without this, cAdvisor silently skips every container. Prometheus then shows only the host-level cgroups (`/docker` and system services) and never an id like `/docker/<long hash>`.

```bash
sudo ls -l /run/docker/containerd/containerd.sock
sudo sed -i -E 's/^#?command_user=.*/command_user="root:root"/' /etc/conf.d/alloy
grep command_user /etc/conf.d/alloy
```

If the first command says the file does not exist, find the real path with `sudo find /run /var/run -name containerd.sock` and use it as `containerd_host` in the next step.

<img width="777" height="162" alt="image" src="https://github.com/user-attachments/assets/6e1f8299-6877-4107-ba32-86475cf3cfdb" />


---

## 24. Write the Alloy Configuration

The configuration is built from parts: a common part for every host, one log block for the host's operating system, and a Docker block for Docker hosts. Alloy comments start with `//`. A line starting with `#` is a syntax error and prevents Alloy from starting.

**Common part (every host):**

```bash
sudo mkdir -p /etc/alloy
sudo tee /etc/alloy/config.alloy > /dev/null << 'EOF'
prometheus.exporter.unix "local_system" {}

prometheus.scrape "local_scrape" {
  targets         = prometheus.exporter.unix.local_system.targets
  forward_to      = [prometheus.remote_write.to_central_prometheus.receiver]
  scrape_interval = "15s"
}

prometheus.remote_write "to_central_prometheus" {
  endpoint {
    url = "http://192.168.74.3:9090/api/v1/write"
  }
}

loki.write "to_central_loki" {
  endpoint {
    url = "http://192.168.74.3:3100/loki/api/v1/push"
  }
}
EOF
```

**Logs on Ubuntu hosts:**

```bash
sudo tee -a /etc/alloy/config.alloy > /dev/null << 'EOF'

loki.source.journal "system_logs" {
  forward_to = [loki.write.to_central_loki.receiver]
  max_age    = "24h"
  labels     = { job = "systemd-journal", host = constants.hostname }
}

loki.source.file "varlogs" {
  targets = [
    { __path__ = "/var/log/*.log", job = "varlogs", host = constants.hostname },
  ]
  forward_to = [loki.write.to_central_loki.receiver]
}
EOF
```

**Logs on Alpine hosts:**

```bash
sudo tee -a /etc/alloy/config.alloy > /dev/null << 'EOF'

loki.source.file "system_logs" {
  targets = [
    { __path__ = "/var/log/messages", job = "syslog",  host = constants.hostname },
    { __path__ = "/var/log/*.log",    job = "varlogs", host = constants.hostname },
  ]
  forward_to = [loki.write.to_central_loki.receiver]
}
EOF
```

**Docker hosts only:**

The two `containerd` lines make container metrics work with Docker 29 and newer, which use the containerd image store. `moby` is the namespace Docker uses for its containers.

```bash
sudo tee -a /etc/alloy/config.alloy > /dev/null << 'EOF'

prometheus.exporter.cadvisor "docker" {
  docker_host          = "unix:///var/run/docker.sock"
  containerd_host      = "/run/docker/containerd/containerd.sock"
  containerd_namespace = "moby"
  storage_duration     = "5m"
}

prometheus.scrape "docker_metrics" {
  targets         = prometheus.exporter.cadvisor.docker.targets
  forward_to      = [prometheus.remote_write.to_central_prometheus.receiver]
  scrape_interval = "15s"
}

discovery.docker "containers" {
  host = "unix:///var/run/docker.sock"
}

discovery.relabel "docker_logs" {
  targets = discovery.docker.containers.targets
  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container_name"
  }
  rule {
    target_label = "job"
    replacement  = "docker"
  }
  rule {
    target_label = "host"
    replacement  = constants.hostname
  }
}

loki.source.docker "containers" {
  host       = "unix:///var/run/docker.sock"
  targets    = discovery.relabel.docker_logs.output
  forward_to = [loki.write.to_central_loki.receiver]
}
EOF
```

**Permissions and syntax check (every host):**

```bash
sudo chown root:root /etc/alloy/config.alloy
sudo chmod 0644 /etc/alloy/config.alloy
alloy fmt /etc/alloy/config.alloy > /dev/null && echo syntax ok
```

What the agent produces:

| Data | Labels | Used by |
|---|---|---|
| Host metrics | `instance` (host name), `job="integrations/unix"` | Host Overview, alerts |
| System logs | `host`, `job` (`systemd-journal`, `syslog` or `varlogs`) | Logs Overview |
| Container metrics | `instance`, `job="integrations/cadvisor"` | Docker Containers, alerts |
| Container logs | `host`, `job="docker"`, `container_name` | Logs Overview |

<img width="777" height="50" alt="image" src="https://github.com/user-attachments/assets/996c40df-bd63-4d7e-a94e-2fce59c33f74" />

---

## 25. Start Alloy

Use `restart`, not `start`, so the new groups and the new run-as user take effect.

**Alpine:**

```bash
sudo rc-update add alloy default
sudo rc-service alloy restart
```

**Ubuntu:**

```bash
sudo systemctl daemon-reload
sudo systemctl enable alloy
sudo systemctl restart alloy
```

On Alpine, OpenRC gives up after five restarts in a short time and marks the service `failed`. In that case `rc-service alloy zap` clears the state, and after the cause is fixed `rc-service alloy start` starts it again.

<img width="699" height="55" alt="image" src="https://github.com/user-attachments/assets/91263269-e1fe-4695-8fe2-36141f359f7d" />


---

## 26. Verify the Agent

On the monitored host:

```bash
curl -s localhost:12345/metrics | grep alloy_component_controller_running_components
```

There must be a `healthy` line with a count above `0` and no `unhealthy` line with a count above `0`.

On Docker hosts also run:

```bash
curl -s localhost:12345/api/v0/component/prometheus.exporter.cadvisor.docker/metrics | grep -c 'id="/docker/'
```

The number must be above `0`. If it is `0`, cAdvisor sees no containers. Alloy writes no log file on Alpine, so stop the service and run it in the foreground for a minute to read cAdvisor's errors:

```bash
sudo rc-service alloy stop
sudo timeout 60 /usr/bin/alloy run /etc/alloy/config.alloy \
  --storage.path=/tmp/alloy-debug --server.http.listen-addr=127.0.0.1:12346 2>&1 \
  | grep -iE 'cadvisor|containerd|docker'
sudo rc-service alloy start
```
<img width="776" height="126" alt="image" src="https://github.com/user-attachments/assets/f6facf01-e12f-4cdb-8fe7-5ea3f46b8412" />


Lines containing `Failed to create existing container` together with `containerd` mean the socket path is wrong (step 23) or Alloy is not running as root.

---

# Part 7. Firewall Rules

## 27. Firewall Rules

The host firewall allows only the flows that monitoring needs. In the project these rules are generated by the host firewall role from the inventory groups.

| Where | Port | Allowed from | Purpose |
|---|---:|---|---|
| `cloud-monitoring` | `9090/tcp` | Project LANs and the tailnet | Prometheus: agents push metrics, Grafana and admins query |
| `cloud-monitoring` | `3100/tcp` | Project LANs and the tailnet | Loki: agents push logs |
| `cloud-monitoring` | `3000/tcp` | Project LANs and the tailnet | Grafana web interface |
| Garage nodes | `3900/tcp` | Load balancers and `cloud-monitoring` | S3 API (shop images and Loki logs) |
| Garage nodes | `3903/tcp` | Garage nodes, load balancers and `cloud-monitoring` | Health and metrics, used by the HAProxy checks |
| Patroni nodes | `8008/tcp` | Patroni nodes, load balancers and `cloud-monitoring` | Patroni health API |
| Load balancers | `8404/tcp` | `cloud-monitoring` and the tailnet | HAProxy statistics |

The HAProxy on the monitoring VM listens on `127.0.0.1:3900` only, so it needs no firewall rule.

---

# Part 8. Alerting to Telegram

Alerts are evaluated by Grafana and sent to a Telegram bot. This part is optional. The role that provisions it skips it when the bot token and chat id are missing from the Vault.

## 28. Create the Telegram Bot

1. In Telegram open `@BotFather`, send `/newbot` and answer the questions. It returns a token that looks like `123456:ABC...`.
2. Send any message to the new bot. For a group, add the bot to the group and send a message there.
3. Open `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser, with your token in place. Find `chat` and its `id`. Group ids are negative, for example `-100123...`.
4. Check that the monitoring VM can reach Telegram:

```bash
curl -sI https://api.telegram.org
```

Store the token and chat id in Ansible Vault as `vault_telegram_bot_token` and `vault_telegram_chat_id`.

---

## 29. Install the Alert Files

```bash
sudo mkdir -p /etc/grafana/provisioning/alerting
sudo chown grafana:grafana /etc/grafana/provisioning/alerting
sudo install -o grafana -g grafana -m 0640 \
  ~/infra/02_Ansible/roles/grafana_dashboards/files/alerting/rules.yml \
  ~/infra/02_Ansible/roles/grafana_dashboards/files/alerting/policies.yml \
  /etc/grafana/provisioning/alerting/
```

Create the contact point. Replace `<BOT_TOKEN>` and `<CHAT_ID>` first. The file contains the token, so keep the permissions as shown:

```bash
sudo nano /etc/grafana/provisioning/alerting/contact-points.yml
```

```yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: telegram
    receivers:
      - uid: telegram-alerts
        type: telegram
        disableResolveMessage: false
        settings:
          bottoken: "<BOT_TOKEN>"
          chatid: "<CHAT_ID>"
          parse_mode: HTML
          message: |-
            {{ range .Alerts }}{{ if eq .Status "firing" }}🔴{{ else }}✅{{ end }} <b>{{ .Labels.alertname }}</b> [{{ .Labels.severity }}]
            {{ .Annotations.summary }}
            {{ end }}
```

```bash
sudo chown grafana:grafana /etc/grafana/provisioning/alerting/contact-points.yml
sudo chmod 0640 /etc/grafana/provisioning/alerting/contact-points.yml
sudo systemctl restart grafana-server
```

Alerting files are read only when Grafana starts, so a restart is required after any change.

The rules:

| Alert | Fires when | Severity |
|---|---|---|
| Host not reporting | No metrics from a host for 3 minutes | critical |
| CPU usage high | Above 90% for 10 minutes | warning |
| Memory usage high | Above 90% for 10 minutes | warning |
| Disk filling up | Above 85% for 10 minutes | warning |
| Disk almost full | Above 95% for 5 minutes | critical |
| Container killed | A container was killed for running out of memory | critical |
| No containers on Docker host | cAdvisor reports, but sees no Docker containers for 3 minutes | critical |
| Error burst in logs | More than 10 error-level log lines in 5 minutes on a host | warning |

The notification policy groups alerts by alert name and host. Critical alerts are sent within about 10 seconds and repeated every hour. Warnings are repeated every 6 hours. A message with a green check mark is sent when a problem clears.

---

# Part 9. Final Validation

## 30. Validate the Whole Chain

**On the monitoring VM**, all four services are running and the S3 proxy reaches Garage:

```bash
systemctl is-active prometheus haproxy loki grafana-server
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3900/
curl -s http://127.0.0.1:3100/ready
```

Four lines `active`, then `403`, then `ready`.

**In Grafana, Explore** with the Prometheus datasource:

```text
count by (instance) (node_uname_info)
count by (instance) (container_last_seen{id=~"/docker/.+"})
```

The first query must list every monitored host. The second must list the Docker hosts (`east-web` and `west-web`).

With the Loki datasource:

```text
{host=~".+"}
```

Recent log lines from the hosts must appear.

**In Garage**, on `cloud-s3`, after the new schema start date has passed and Loki has run for a while:

```bash
sudo garage bucket info loki-logs
```

The object count must be above `0`. Index and chunk objects appear when Loki flushes data, which can take up to about 30 minutes.

**In the Grafana web interface:**

- Dashboards, folder Infrastructure: Host Overview, Logs Overview and Docker Containers.
- Dashboards, folder Project Monitoring: Project Overview.
- Connections, Data sources: Prometheus (default) and Loki are listed, and the connection test succeeds.
- Alerting, Alert rules: folder Alerts with 8 rules in three groups.
- Alerting, Contact points: open `telegram` and press Test. A test message must arrive in the chat.

---

## Ansible Automation

The manual steps above are automated by these playbooks, run in this order from the `02_Ansible` directory:

| Order | Command | What it does |
|---:|---|---|
| 1 | `ansible-playbook 03_FIREWALL_DNS.yml --ask-vault-pass` | Firewall rules, including port `3900` for the monitoring server (step 8) |
| 2 | `ansible-playbook 04_S3_STORAGE_service.yml --tags garage_loki --ask-vault-pass` | Log bucket and key in Garage (step 7) |
| 3 | `ansible-playbook 09_MONITORING_server.yml --ask-vault-pass` | Prometheus, HAProxy, Loki and Grafana, then datasources, dashboards and alerts (steps 1 to 20 and 28 to 29) |
| 4 | `ansible-playbook 10_MONITORING_agents.yml --ask-vault-pass` | Alloy on every host (steps 21 to 26) |

The Vault must contain `vault_garage_loki_access_key`, `vault_garage_loki_secret_key`, `vault_grafana_admin_password` and, for alerts, `vault_telegram_bot_token` and `vault_telegram_chat_id`.

The log storage can be switched off with `loki_s3_enabled: false` in the `monitoring_server` role. Loki then stores logs on the local disk again.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| Loki does not become ready | A configuration error, or S3 is unreachable | `sudo journalctl -u loki -n 50 --no-pager` shows the reason. Check that the S3 proxy answers `403` |
| Loki log shows `AccessDenied`, `NoSuchBucket` or `SignatureDoesNotMatch` | Missing bucket, key without access, or a key and secret that do not match | Repeat step 7, and check the values in the Loki configuration |
| `curl http://127.0.0.1:3900/` times out | HAProxy is not running, or no Garage node accepts the monitoring server | `systemctl status haproxy`, then repeat step 8 |
| `curl http://127.0.0.1:3900/` prints `503` | HAProxy sees no healthy Garage node | Check `sudo garage status` on `cloud-s3` and the firewall rule for port `3903` |
| Grafana log shows `the same UID is used more than once` | Two dashboard providers see the same file, or a dashboard was imported by hand | Check that the two folders in step 17 are separate, and delete any hand-imported copy, including the ones under Recently deleted |
| Dashboards exist but panels are empty | The datasources are missing or named differently | Repeat step 18 and test the queries in Explore |
| Docker Containers shows no data | cAdvisor sees no containers | Repeat steps 23 and 26. The log line `Failed to create existing container ... containerd` points to the socket path or to Alloy not running as root |
| Alloy fails to start with exit code 1 | A syntax error in `/etc/alloy/config.alloy` | `alloy fmt /etc/alloy/config.alloy`. Check for lines starting with `#` instead of `//` |
| Alloy shows `failed` on Alpine | OpenRC stopped restarting it after repeated crashes | Fix the cause, then `rc-service alloy zap` and `rc-service alloy start` |
| A host sends no metrics | The agent is stopped, or the firewall blocks port `9090` | `rc-service alloy status` or `systemctl status alloy`, and `curl http://192.168.74.3:9090/-/ready` from that host |
| No Telegram message | Wrong token or chat id, the bot was never messaged, or no access to Telegram | Check the values, send the bot a message first, and test `curl -sI https://api.telegram.org`. The Grafana log shows the reason |
| Alert files changed but nothing happens | Alerting files are read only at startup | `sudo systemctl restart grafana-server` |

---

## Updating or Removing

- **A new Prometheus or Loki version:** repeat the download and `install` step with the new version number, then restart the service.
- **A configuration change:** edit the file, validate it (`promtool check config`, Loki `-verify-config`, `haproxy -c`, `alloy fmt`), then restart the service.
- **Remove the stack:** stop and disable `prometheus`, `loki`, `haproxy` and `grafana-server`, delete their service files and binaries, delete `/etc/prometheus`, `/etc/loki`, `/var/lib/prometheus`, `/var/lib/loki`, run `sudo apt-get remove grafana haproxy`, then `sudo systemctl daemon-reload`. Logs already stored in the `loki-logs` bucket stay in Garage until the bucket is deleted.

## Result

The infrastructure now has a central monitoring system with:

- One Grafana Alloy agent on every virtual machine, for host metrics, system logs and container data
- Prometheus for metrics, with a push-based design that needs no open ports on the monitored machines
- Loki for logs with 7-day retention, stored in the separate Garage `loki-logs` bucket
- A local HAProxy that sends log writes to a healthy Garage node and falls back across zones
- Dashboards and alert rules provisioned from the repository, so a rebuilt server gets them back unchanged
- Telegram notifications for outages, resource problems and error bursts
- Host firewall rules that allow only the flows monitoring needs
- Fully automated deployment with Ansible and a documented manual procedure
