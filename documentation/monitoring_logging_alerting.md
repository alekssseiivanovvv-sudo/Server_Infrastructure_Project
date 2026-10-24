# Monitoring stack by hand: server, Grafana content and agents

Manual equivalent of three Ansible roles: `monitoring_server`, `grafana_dashboards` and `monitoring_agents` (playbooks `09_MONITORING_server.yml` and `10_MONITORING_agents.yml`). The monitoring VM runs Ubuntu at 192.168.74.3.

## Order of work

1. **Part 1:** install Prometheus, Loki and Grafana on the monitoring VM.
2. **Part 2:** give Grafana its datasources and dashboards.
3. **Part 3:** install the Alloy agent on every host, so data starts to flow.
4. **Part 4:** set up Telegram alerts (optional).
5. **Part 5:** check the whole chain from end to end.

Parts 1, 2 and 4 run on the monitoring VM only. Part 3 is repeated on each monitored host.

## Part 1. The server: Prometheus, Loki and Grafana

### What Part 1 builds

Three services on one Ubuntu machine, all started by systemd:

- **Prometheus 3.5.0** on port 9090. It also accepts metrics pushed by the Alloy agents (remote write receiver).
- **Loki 3.5.1** on port 3100 (HTTP) and 9095 (gRPC). It stores logs for 7 days.
- **Grafana OSS** (latest from the Grafana apt repository) on port 3000.

The role does **not** create Grafana datasources or dashboards. That is the separate `grafana_dashboards` role. Part 2 covers that.

Values used below (they come from the playbook variables):

| Item | Value |
|---|---|
| Prometheus version | 3.5.0 |
| Loki version | 3.5.1 |
| Prometheus run-as user | prometheus_sysuser |
| Grafana admin user | admin |
| Grafana admin password | your choice (the role takes it from the vault) |

Run everything as a user with sudo. The VM needs internet access to GitHub and apt.grafana.com.

### Step 1. Install base packages

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg unzip wget
```

### Step 2. Create the Prometheus user

The role runs Prometheus under a normal login account named `prometheus_sysuser` (its password hash comes from the vault list `vault_admin_users`). To copy that behaviour:

```bash
sudo useradd -m -s /bin/bash prometheus_sysuser
sudo passwd prometheus_sysuser
```

If you do not need a login on that account, a system user without a shell is safer: `sudo useradd --system --no-create-home --shell /usr/sbin/nologin prometheus_sysuser`. The rest of the steps work either way.

### Step 3. Prometheus directories

```bash
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo chown prometheus_sysuser:prometheus_sysuser /etc/prometheus /var/lib/prometheus
sudo chmod 0755 /etc/prometheus
sudo chmod 0750 /var/lib/prometheus
```

### Step 4. Download and install Prometheus

```bash
wget -O /tmp/prometheus-3.5.0.linux-amd64.tar.gz https://github.com/prometheus/prometheus/releases/download/v3.5.0/prometheus-3.5.0.linux-amd64.tar.gz
tar -xzf /tmp/prometheus-3.5.0.linux-amd64.tar.gz -C /tmp
sudo install -o root -g root -m 0755 /tmp/prometheus-3.5.0.linux-amd64/prometheus /tmp/prometheus-3.5.0.linux-amd64/promtool /usr/local/bin/
prometheus --version
```

### Step 5. Prometheus configuration

```bash
sudo tee /etc/prometheus/prometheus.yml > /dev/null << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - localhost:9090
EOF
sudo chown prometheus_sysuser:prometheus_sysuser /etc/prometheus/prometheus.yml
sudo chmod 0644 /etc/prometheus/prometheus.yml
promtool check config /etc/prometheus/prometheus.yml
```

The last command must say SUCCESS. Host and container metrics do not come from scraping here: the Alloy agents push them to this server.

Optional: the role also adds a `node_exporter` job for every host in the inventory group `node_exporter_agents` (currently empty, its members are commented out). To scrape such hosts by hand, append this to the file and list the real addresses:

```yaml
  - job_name: node_exporter
    static_configs:
      - targets:
          - 192.168.74.1:9100
```

### Step 6. Prometheus systemd service

The two flags at the end matter: `--web.enable-remote-write-receiver` is what lets the Alloy agents push metrics, and `--web.enable-lifecycle` allows a config reload over HTTP.

```bash
sudo tee /etc/systemd/system/prometheus.service > /dev/null << 'EOF'
[Unit]
Description=Prometheus monitoring server
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus_sysuser
Group=prometheus_sysuser
Type=simple
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --web.enable-lifecycle --web.enable-remote-write-receiver
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
```

### Step 7. Create the Loki user and directories

```bash
sudo useradd --system --user-group --no-create-home --shell /usr/sbin/nologin loki
sudo mkdir -p /etc/loki /var/lib/loki/chunks /var/lib/loki/rules /var/lib/loki/compactor
sudo chown loki:loki /etc/loki
sudo chown -R loki:loki /var/lib/loki
sudo chmod 0755 /etc/loki
sudo chmod -R 0750 /var/lib/loki
```

### Step 8. Download and install Loki

```bash
wget -O /tmp/loki-linux-amd64-3.5.1.zip https://github.com/grafana/loki/releases/download/v3.5.1/loki-linux-amd64.zip
unzip -o /tmp/loki-linux-amd64-3.5.1.zip -d /tmp
sudo install -o root -g root -m 0755 /tmp/loki-linux-amd64 /usr/local/bin/loki
loki --version
```

### Step 9. Loki configuration

This keeps logs for 168 hours (7 days), stores them on local disk and runs without authentication.

```bash
sudo tee /etc/loki/config.yml > /dev/null << 'EOF'
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

limits_config:
  retention_period: 168h

compactor:
  working_directory: /var/lib/loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: filesystem

analytics:
  reporting_enabled: false
EOF
sudo chown loki:loki /etc/loki/config.yml
sudo chmod 0644 /etc/loki/config.yml
sudo -u loki /usr/local/bin/loki -config.file=/etc/loki/config.yml -verify-config
```

The last command should report that the config is valid.

### Step 10. Loki systemd service

```bash
sudo tee /etc/systemd/system/loki.service > /dev/null << 'EOF'
[Unit]
Description=Loki log aggregation server
Wants=network-online.target
After=network-online.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/config.yml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
```

### Step 11. Install Grafana from the official apt repository

```bash
sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
sudo chmod 0644 /etc/apt/keyrings/grafana.asc
echo 'deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main' | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana
```

### Step 12. Grafana admin account and home dashboard

Open the config file:

```bash
sudo nano /etc/grafana/grafana.ini
```

In the `[security]` section set these two lines. Remove the leading semicolon if the line is commented out:

```ini
admin_user=admin
admin_password=CHANGE_ME
```

In the `[dashboards]` section set the home dashboard:

```ini
default_home_dashboard_path=/var/lib/grafana/dashboards/project/project-overview.json
```

The role points at `project/project-overview.json`. If that file does not exist on your machine, Grafana falls back to its normal home page. Point the setting at a dashboard that does exist, for example `/var/lib/grafana/dashboards/ansible/alloy-host-overview.json`, or leave the line out.

Then restore the original ownership and permissions of the file:

```bash
sudo chown root:grafana /etc/grafana/grafana.ini
sudo chmod 0640 /etc/grafana/grafana.ini
```

### Step 13. Start everything

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus loki grafana-server
systemctl is-active prometheus loki grafana-server
```

All three lines must say `active`. If one does not, read its log, for example `sudo journalctl -u loki -n 50 --no-pager`.

### Step 14. Set the Grafana admin password

The `admin_password` line in grafana.ini only counts the first time Grafana creates its database. If Grafana has started before, set the password explicitly. The role does the same:

```bash
sudo grafana cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini admin reset-admin-password 'CHANGE_ME'
```

If `grafana cli` is not recognised, use the older command name: `sudo grafana-cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini admin reset-admin-password 'CHANGE_ME'`.

### Step 15. Check that it works

```bash
curl -s http://127.0.0.1:9090/-/ready
curl -s http://127.0.0.1:3100/ready
curl -s http://127.0.0.1:3000/api/health
```

Expected: Prometheus says it is ready, Loki says `ready` (it can take about 15 seconds after start), and Grafana returns JSON with `database: ok`. Then open `http://192.168.74.3:3000` and log in as `admin`.

The agents send data to these addresses (set in the Alloy playbook):

- metrics: `http://192.168.74.3:9090/api/v1/write`
- logs: `http://192.168.74.3:3100/loki/api/v1/push`

## Part 2. Grafana content: datasources and dashboards

Manual equivalent of the role `grafana_dashboards` (the second play of `09_MONITORING_server.yml`), except for the alerting files, which are Part 4. Do it after Part 1 is finished and Grafana is running. The datasources come from a provisioning file here, not from clicking in the web UI.

### What Part 2 builds

- Two datasources, Prometheus (default) and Loki, with fixed ids `prometheus-uid` and `loki-uid`. The dashboards and alert rules depend on these ids.
- Two dashboard providers that watch separate folders. The folders must not overlap, because Grafana reads folders recursively and one file seen by two providers causes a duplicate uid error that blocks both.
  - `/var/lib/grafana/dashboards/ansible` is shown in the folder **Infrastructure**. It holds Host Overview, Logs Overview and Docker Containers.
  - `/var/lib/grafana/dashboards/project` is shown in the folder **Project Monitoring**. It holds `project-overview.json`, which is also the Grafana home page from Step 12.

The dashboard and alert files are too big to paste, so they are copied from the project repository. The next step puts a copy of the repository on the VM.

### Step 16. Get the repository files onto the VM

```bash
sudo apt-get install -y git
git clone https://github.com/alekssseiivanovvv-sudo/Server_Infrastructure_Project.git ~/infra
```

If you cannot clone the repository from the VM, copy the same files with `scp` from the automation node and keep the same folder layout. The paths used below are:

- `~/infra/ansible/roles/grafana_dashboards/files/dashboards/` for the three dashboards
- `~/infra/ansible/files/grafana/dashboards/project-overview.json` for the project dashboard
- `~/infra/ansible/roles/grafana_dashboards/files/alerting/` for the alert rules and policy

### Step 17. Create the provisioning and dashboard folders

```bash
sudo mkdir -p /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards/ansible /var/lib/grafana/dashboards/project
sudo chown grafana:grafana /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards/ansible /var/lib/grafana/dashboards/project
sudo chmod 0755 /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards /var/lib/grafana/dashboards/ansible /var/lib/grafana/dashboards/project
```

### Step 18. Remove old and conflicting provisioning files

The role deletes files that older versions of the setup created. They would define the same datasources or dashboards a second time:

```bash
sudo rm -f /etc/grafana/provisioning/datasources/project.yml /etc/grafana/provisioning/datasources/sample.yaml /etc/grafana/provisioning/datasources/datasource.yaml /etc/grafana/provisioning/dashboards/project.yml
```

### Step 19. Datasources

The `deleteDatasources` block removes any datasource already named Prometheus or Loki, for example one you created by hand in the web UI. That is how the ids stay fixed.

```bash
sudo tee /etc/grafana/provisioning/datasources/ansible.yml > /dev/null << 'EOF'
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
EOF
sudo chown grafana:grafana /etc/grafana/provisioning/datasources/ansible.yml
sudo chmod 0640 /etc/grafana/provisioning/datasources/ansible.yml
```

### Step 20. Dashboard providers

```bash
sudo tee /etc/grafana/provisioning/dashboards/ansible.yml > /dev/null << 'EOF'
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
EOF
sudo chown grafana:grafana /etc/grafana/provisioning/dashboards/ansible.yml
sudo chmod 0640 /etc/grafana/provisioning/dashboards/ansible.yml
```

The Infrastructure folder cannot be edited in the web UI (`allowUiUpdates: false`), so the files stay the single source of truth. The Project Monitoring folder can be edited.

### Step 21. Copy the dashboards

Copy the files as they are. Do not run them through a template engine, because the legends contain `{{ }}` placeholders that belong to Grafana.

```bash
sudo install -o grafana -g grafana -m 0644 ~/infra/ansible/roles/grafana_dashboards/files/dashboards/alloy-host-overview.json ~/infra/ansible/roles/grafana_dashboards/files/dashboards/alloy-logs-overview.json ~/infra/ansible/roles/grafana_dashboards/files/dashboards/alloy-docker-containers.json /var/lib/grafana/dashboards/ansible/
sudo install -o grafana -g grafana -m 0644 ~/infra/ansible/files/grafana/dashboards/project-overview.json /var/lib/grafana/dashboards/project/project-overview.json
```

### Step 22. Clean out old dashboards

The role deletes every other `*.json` in the `ansible` folder, plus files of earlier attempts. Skip this step on a fresh machine.

```bash
sudo find /var/lib/grafana/dashboards/ansible -name '*.json' ! -name 'alloy-host-overview.json' ! -name 'alloy-logs-overview.json' ! -name 'alloy-docker-containers.json' -delete
sudo rm -f /var/lib/grafana/dashboards/alloy-host-overview.json /var/lib/grafana/dashboards/alloy-logs-overview.json
sudo rm -f /tmp/fix_dashboards.py /tmp/alloy-*.json /tmp/loki-logs.json /tmp/docker-cadvisor.json /tmp/postgresql.json
```

Grafana removes a dashboard from its folder a few seconds after its file is deleted, because `disableDeletion` is false.

## Part 3. The agents: Grafana Alloy on every host

Manual equivalent of the role `monitoring_agents` (playbook `10_MONITORING_agents.yml`). Repeat this part on every machine you want to monitor; the role runs it on all hosts of the inventory group `alloy_agents`. Alloy collects host metrics and logs, plus container metrics and logs on Docker hosts, and pushes them to the monitoring VM. It supports Alpine (OpenRC) and Ubuntu (systemd).

### What Part 3 builds

- On every host: host metrics every 15 seconds, pushed to Prometheus with the labels `instance` (the host name) and `job` set to `integrations/unix`.
- On every host: logs pushed to Loki with the label `host`. Alpine hosts send `/var/log/messages` and `/var/log/*.log`. Ubuntu hosts send the systemd journal and `/var/log/*.log`.
- On Docker hosts only (the two web worker VMs): container metrics from Alloy's built-in cAdvisor with `job` set to `integrations/cadvisor`, and container logs with `job` set to `docker`.

| Item | Value |
| --- | --- |
| Monitoring VM | 192.168.74.3 |
| Metrics push URL | `http://192.168.74.3:9090/api/v1/write` |
| Logs push URL | `http://192.168.74.3:3100/loki/api/v1/push` |
| Docker host | yes on the web worker VMs, no on all others |

Before you start, check from the host that the server answers:

```bash
curl -s http://192.168.74.3:9090/-/ready
curl -s http://192.168.74.3:3100/ready
```

Both should report that they are ready.

### Step 23. Install Alloy on Alpine hosts

Skip this step on Ubuntu hosts. The `shadow` package provides the `usermod` command used in the next steps.

```bash
sudo apk update
sudo apk add alloy alloy-openrc shadow
```

### Step 24. Install Alloy on Ubuntu hosts

Skip this step on Alpine hosts. On the monitoring VM the Grafana repository already exists from Step 11, so only the last two commands are needed there.

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates gnupg wget
sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
sudo chmod 0644 /etc/apt/keyrings/grafana.asc
echo 'deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main' | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y alloy
```

### Step 25. Let Alloy read logs and talk to Docker

The `alloy` user needs to be in the groups that can read the system logs, and in the `docker` group on Docker hosts. A running process does not see a new group until it is restarted, which Step 28 does.

Alpine:

```bash
sudo usermod -aG wheel alloy
sudo usermod -aG docker alloy    # Docker hosts only
```

Ubuntu:

```bash
sudo usermod -aG adm,systemd-journal alloy
sudo usermod -aG docker alloy    # Docker hosts only
```

### Step 26. Docker hosts only: run Alloy as root

CAdvisor reads container details from Docker's own containerd socket, and only root may use it. Without this step cAdvisor skips every container silently, and Prometheus only shows host-level ids such as `/docker`, never `/docker/<long hash>`. The role does this on Alpine Docker hosts only.

```bash
sudo ls -l /run/docker/containerd/containerd.sock
sudo sed -i -E 's/^#?command_user=.*/command_user="root:root"/' /etc/conf.d/alloy
grep command_user /etc/conf.d/alloy
```

If the first command says the file does not exist, find the real path with `sudo find /run /var/run -name containerd.sock` and use it as `containerd_host` in Step 27.

### Step 27. Write the Alloy configuration

The file is built from parts: a common part for all hosts, one log block for the host's operating system, and the Docker block on Docker hosts only. Run the first command on every host, then only the ones that apply.

**1. Common part (every host)**

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

**2a. Logs on Ubuntu hosts**

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

**2b. Logs on Alpine hosts**

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

**3. Docker hosts only**

The two `containerd` lines are what makes container metrics work with Docker 29 and newer. The `moby` namespace is the one Docker uses for its containers.

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

**4. Permissions and syntax check (every host)**

```bash
sudo chown root:root /etc/alloy/config.alloy
sudo chmod 0644 /etc/alloy/config.alloy
alloy fmt /etc/alloy/config.alloy > /dev/null && echo syntax ok
```

### Step 28. Start Alloy

Use restart, not start, so that the new groups and the new run-as user apply.

Alpine:

```bash
sudo rc-update add alloy default
sudo rc-service alloy restart
```

Ubuntu:

```bash
sudo systemctl daemon-reload
sudo systemctl enable alloy
sudo systemctl restart alloy
```

### Step 29. Check the agent on the host

```bash
curl -s localhost:12345/metrics | grep alloy_component_controller_running_components
```

You should see a `healthy` line with a count above 0, and no `unhealthy` line with a count above 0.

On Docker hosts also run:

```bash
curl -s localhost:12345/api/v0/component/prometheus.exporter.cadvisor.docker/metrics | grep -c 'id="/docker/'
```

The number must be above 0. If it is 0, cAdvisor sees no containers. Alloy writes no log file on Alpine, so run it in the foreground for a minute to read cAdvisor's errors:

```bash
sudo rc-service alloy stop
sudo timeout 60 /usr/bin/alloy run /etc/alloy/config.alloy --storage.path=/tmp/alloy-debug --server.http.listen-addr=127.0.0.1:12346 2>&1 | grep -iE 'cadvisor|containerd|docker'
sudo rc-service alloy start
```

Lines saying `Failed to create existing container` together with `containerd` mean the socket path is wrong (Step 26) or Alloy is not running as root.

## Part 4. Alerting to Telegram (optional)

Runs on the monitoring VM, once the agents deliver data. It is the alerting part of the role `grafana_dashboards`.

### Step 30. Alerting to Telegram (optional)

Skip this step if you do not want alerts. The role itself skips it when the bot token and chat id are not set in the vault.

**Create the bot and find the chat id**

1. In Telegram open **@BotFather**, send `/newbot` and follow the questions. It gives you a token that looks like `123456:ABC...`.
2. Send any message to the new bot. For a group, add the bot to the group and send a message there.
3. Open `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser, with your token in place. Find `chat` and its `id`. Group ids are negative, like `-100123...`.
4. Check that the VM can reach Telegram: `curl -sI https://api.telegram.org`.

**Install the files**

```bash
sudo mkdir -p /etc/grafana/provisioning/alerting
sudo chown grafana:grafana /etc/grafana/provisioning/alerting
sudo install -o grafana -g grafana -m 0640 ~/infra/ansible/roles/grafana_dashboards/files/alerting/rules.yml ~/infra/ansible/roles/grafana_dashboards/files/alerting/policies.yml /etc/grafana/provisioning/alerting/
```

**Create the contact point.** Replace `YOUR_BOT_TOKEN` and `YOUR_CHAT_ID` before running it. This file contains the token, so keep its permissions as shown:

```bash
sudo tee /etc/grafana/provisioning/alerting/contact-points.yml > /dev/null << 'EOF'
apiVersion: 1

contactPoints:
  - orgId: 1
    name: telegram
    receivers:
      - uid: telegram-alerts
        type: telegram
        disableResolveMessage: false
        settings:
          bottoken: "YOUR_BOT_TOKEN"
          chatid: "YOUR_CHAT_ID"
          parse_mode: HTML
          message: |-
            {{ range .Alerts }}{{ if eq .Status "firing" }}🔴{{ else }}✅{{ end }} <b>{{ .Labels.alertname }}</b> [{{ .Labels.severity }}]
            {{ .Annotations.summary }}
            {{ end }}
EOF
sudo chown grafana:grafana /etc/grafana/provisioning/alerting/contact-points.yml
sudo chmod 0640 /etc/grafana/provisioning/alerting/contact-points.yml
```

**What the rules do**

| Alert | Fires when | Severity |
|---|---|---|
| Host not reporting | no metrics from a host for 3 minutes | critical |
| CPU usage high | above 90% for 10 minutes | warning |
| Memory usage high | above 90% for 10 minutes | warning |
| Disk filling up | above 85% for 10 minutes | warning |
| Disk almost full | above 95% for 5 minutes | critical |
| Container killed | a container was killed for running out of memory | critical |
| No containers on Docker host | cAdvisor reports but sees no Docker containers for 3 minutes | critical |
| Error burst in logs | more than 10 error lines in 5 minutes on a host | warning |

The policy groups alerts by alert name and host, repeats critical alerts every hour and everything else every 6 hours, and sends a message when a problem clears.

## Part 5. Final check and troubleshooting

Run this once the server, the Grafana content, the agents and (if wanted) the alerts are in place.

### Step 31. Restart Grafana and check

Dashboard files are picked up within about 10 seconds. Datasources and alerting files are read only when Grafana starts, so restart it once:

```bash
sudo systemctl restart grafana-server
sleep 15
sudo journalctl -u grafana-server --since '2 minutes ago' --no-pager | grep -iE 'duplicate|provisioning.*(error|fail)'
```

The last command should print nothing. Then check in the web UI:

- **Dashboards:** folder Infrastructure has Host Overview, Logs Overview and Docker Containers. Folder Project Monitoring has the project overview.
- **Connections, Data sources:** Prometheus (default) and Loki are listed and the Save and test button says it works.
- **Alerting, Alert rules:** if you did Step 30, the folder Alerts has 8 rules in three groups.
- **Alerting, Contact points:** open telegram and press Test. A test message should arrive in the chat within seconds.

Then confirm that the agents deliver data. In Grafana, open Explore. With the Prometheus datasource, `count by (instance) (node_uname_info)` should list every host, and `count by (instance) (container_last_seen{id=~"/docker/.+"})` should list the Docker hosts. With the Loki datasource, `{host=~".+"}` should show recent log lines. The host dashboards fill within a minute. The Docker Containers dashboard fills once cAdvisor sees containers (Step 26).

### Troubleshooting

- **Log line `the same UID is used more than once`:** two dashboard providers see the same file, or a dashboard with that id was imported by hand. Check that the two folders in Step 20 are separate and not nested, and delete any hand-imported copy in the web UI, including Recently deleted.
- **Dashboards in the folder but panels empty:** the datasources are missing or named differently. Check Step 19, then check data on the Explore page.
- **Docker Containers shows no data:** the Docker hosts need the Alloy agent with the cAdvisor settings from Part 3. This server only stores what the agents send.
- **No Telegram message:** check the token and chat id, check that the bot was messaged first, and check that the VM can reach `api.telegram.org`. The Grafana log shows the reason (`journalctl -u grafana-server`).
- **Alerting files changed but nothing happens:** restart Grafana, because these files are read only at startup.

## Security notes

- Prometheus accepts remote writes and Loki accepts pushes with no authentication, and both listen on all interfaces. Allow ports 9090, 3100 and 3000 only from the internal network and the VPN, using the firewall.
- The Grafana password lives in grafana.ini in plain text. The file is readable only by root and the grafana group (mode 0640).

## Updating or undoing

- **New Prometheus or Loki version:** repeat the download and `install` step with the new version number, then `sudo systemctl restart prometheus` or `sudo systemctl restart loki`.
- **Config change:** edit the file, check it (`promtool check config` or Loki `-verify-config`), then restart the service.
- **Remove everything:** stop and disable the three services, delete `/etc/systemd/system/prometheus.service` and `loki.service`, `/usr/local/bin/prometheus`, `promtool` and `loki`, `/etc/prometheus`, `/etc/loki`, `/var/lib/prometheus`, `/var/lib/loki`, run `sudo apt-get remove grafana`, then `sudo systemctl daemon-reload`.
