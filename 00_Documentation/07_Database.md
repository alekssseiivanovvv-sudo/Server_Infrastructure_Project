# Manual PostgreSQL Cluster Installation with Patroni and etcd
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Patroni](https://img.shields.io/badge/Patroni-336791?style=for-the-badge&logoColor=white)](https://github.com/patroni/patroni)
[![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](https://ubuntu.com/)

This guide describes the manual installation of a PostgreSQL cluster with automatic failover. etcd runs on three virtual machines and stores the cluster coordination state. Patroni manages PostgreSQL on the two database nodes.

## Lab Topology

| Virtual machine | Node name | IP address | Services |
|---|---|---|---|
| East DB | `east_db` | `192.168.72.4` | etcd, Patroni, PostgreSQL |
| West DB | `west_db` | `192.168.73.4` | etcd, Patroni, PostgreSQL |
| Cloud quorum | `cloud_quorum` | `192.168.74.5` | Third etcd member |

## 1. Install etcd

### 1.1 Install the Packages

**Run on:** `east_db`, `west_db`, `cloud_quorum`.

```bash
sudo apt update
sudo apt install -y etcd-server etcd-client curl
```

<img width="1577" height="967" alt="image" src="https://github.com/user-attachments/assets/0826ed56-6f84-49c5-86de-b885270a2f87" />


### 1.2 Create the Data Directory

**Run on:** `east_db`, `west_db`, `cloud_quorum`.

```bash
sudo install -d -o etcd -g etcd -m 0700 /var/lib/etcd-project
```

<img width="1577" height="967" alt="image" src="https://github.com/user-attachments/assets/db809fc7-fb03-4d53-a912-c4b86c23b073" />


### 1.3 Configure east_db

**Run only on:** `east_db` (`192.168.72.4`).

```bash
sudo tee /etc/default/etcd-project >/dev/null <<'EOF'
ETCD_NAME="east_db"
ETCD_DATA_DIR="/var/lib/etcd-project"

ETCD_LISTEN_CLIENT_URLS="http://127.0.0.1:2379,http://192.168.72.4:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.72.4:2379"

ETCD_LISTEN_PEER_URLS="http://192.168.72.4:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.72.4:2380"

ETCD_INITIAL_CLUSTER="east_db=http://192.168.72.4:2380,west_db=http://192.168.73.4:2380,cloud_quorum=http://192.168.74.5:2380"
ETCD_INITIAL_CLUSTER_TOKEN="project-postgres-etcd3-v1"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF
```

### 1.4 Configure west_db

**Run only on:** `west_db` (`192.168.73.4`).

```bash
sudo tee /etc/default/etcd-project >/dev/null <<'EOF'
ETCD_NAME="west_db"
ETCD_DATA_DIR="/var/lib/etcd-project"

ETCD_LISTEN_CLIENT_URLS="http://127.0.0.1:2379,http://192.168.73.4:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.73.4:2379"

ETCD_LISTEN_PEER_URLS="http://192.168.73.4:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.73.4:2380"

ETCD_INITIAL_CLUSTER="east_db=http://192.168.72.4:2380,west_db=http://192.168.73.4:2380,cloud_quorum=http://192.168.74.5:2380"
ETCD_INITIAL_CLUSTER_TOKEN="project-postgres-etcd3-v1"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF
```

### 1.5 Configure cloud_quorum

**Run only on:** `cloud_quorum` (`192.168.74.5`).

```bash
sudo tee /etc/default/etcd-project >/dev/null <<'EOF'
ETCD_NAME="cloud_quorum"
ETCD_DATA_DIR="/var/lib/etcd-project"

ETCD_LISTEN_CLIENT_URLS="http://127.0.0.1:2379,http://192.168.74.5:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.74.5:2379"

ETCD_LISTEN_PEER_URLS="http://192.168.74.5:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.74.5:2380"

ETCD_INITIAL_CLUSTER="east_db=http://192.168.72.4:2380,west_db=http://192.168.73.4:2380,cloud_quorum=http://192.168.74.5:2380"
ETCD_INITIAL_CLUSTER_TOKEN="project-postgres-etcd3-v1"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF
```

<img width="1572" height="844" alt="image" src="https://github.com/user-attachments/assets/4ef6dc66-f943-4937-a1ca-ee48708b0a7e" />

### 1.6 Create the etcd systemd Service

**Run on:** `east_db`, `west_db`, `cloud_quorum`.

```bash
sudo tee /etc/systemd/system/etcd.service >/dev/null <<'EOF'
[Unit]
Description=Project etcd v3
After=network-online.target
Wants=network-online.target

[Service]
User=etcd
Group=etcd
EnvironmentFile=/etc/default/etcd-project
ExecStart=/usr/bin/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

<img width="1572" height="844" alt="image" src="https://github.com/user-attachments/assets/9c8d4c36-3f3e-4216-a3b0-ab8cef4413f3" />


Set the file owner and permissions:

```bash
sudo chown root:root /etc/default/etcd-project
sudo chmod 0644 /etc/default/etcd-project
```

<img width="1572" height="323" alt="image" src="https://github.com/user-attachments/assets/cb76f51d-3e01-4799-8ae4-b733fb745814" />


### 1.7 Start etcd

**Run on:** `east_db`, `west_db`, `cloud_quorum`.

```bash
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
sudo systemctl status etcd --no-pager
```

<img width="1572" height="844" alt="image" src="https://github.com/user-attachments/assets/84fdfd69-09a0-4c59-bd19-0191265e0643" />


Start etcd on all three virtual machines before checking cluster health.

### 1.8 Verify the etcd Cluster

**Run on any one etcd node**, for example `east_db`.

```bash
export ETCDCTL_API=3

etcdctl \
  --endpoints=http://192.168.72.4:2379,http://192.168.73.4:2379,http://192.168.74.5:2379 \
  endpoint health

etcdctl \
  --endpoints=http://192.168.72.4:2379,http://192.168.73.4:2379,http://192.168.74.5:2379 \
  member list \
  --write-out=table

etcdctl \
  --endpoints=http://192.168.72.4:2379,http://192.168.73.4:2379,http://192.168.74.5:2379 \
  endpoint status \
  --write-out=table
```

<img width="1572" height="603" alt="image" src="https://github.com/user-attachments/assets/af3c9100-cf70-4f47-a24c-625edb2665d6" />


## 2. Install PostgreSQL and Patroni

Install PostgreSQL and Patroni on the two database nodes only. The `cloud_quorum` VM runs etcd only.

### 2.1 Install PostgreSQL

**Run on:** `east_db`, `west_db`.

```bash
sudo apt update
sudo apt install -y postgresql postgresql-client
```

<img width="1588" height="1015" alt="image" src="https://github.com/user-attachments/assets/088eb013-bd10-49a0-a54e-47260345438f" />


### 2.2 Install Patroni

**Run on:** `east_db`, `west_db`.

```bash
sudo apt install -y patroni python3-psycopg2 python3-etcd python3-etcd3gw curl sudo util-linux
```

<img width="1574" height="1022" alt="image" src="https://github.com/user-attachments/assets/409cb8a7-3367-48d9-952a-8386e76655b1" />


### 2.3 Identify the Installed PostgreSQL Version

**Run on:** `east_db`, `west_db`.

```bash
ls -1 /usr/lib/postgresql
PG_MAJOR=$(ls -1 /usr/lib/postgresql | sort -V | tail -n 1)
PG_BIN_DIR="/usr/lib/postgresql/${PG_MAJOR}/bin"
echo "PostgreSQL version: ${PG_MAJOR}"
echo "PostgreSQL binaries: ${PG_BIN_DIR}"
```

<img width="1536" height="1021" alt="image" src="https://github.com/user-attachments/assets/eceed1e4-c406-4a65-8522-dbe4acb02f86" />


### 2.4 Disable the Default PostgreSQL Instance

Patroni must manage the PostgreSQL process, so disable the default instance created by the package installer.

**Run on:** `east_db`, `west_db`.

```bash
sudo pg_ctlcluster "$PG_MAJOR" main stop
sudo systemctl disable --now "postgresql@${PG_MAJOR}-main.service"
sudo systemctl mask "postgresql@${PG_MAJOR}-main.service"
sudo systemctl disable --now postgresql.service
```

<img width="1536" height="522" alt="image" src="https://github.com/user-attachments/assets/da03c2e3-9316-4865-a396-3d1d00eb04b1" />


Check the service state:

```bash
systemctl is-active "postgresql@${PG_MAJOR}-main.service"
```

Expected result: `inactive`.

<img width="1531" height="496" alt="image" src="https://github.com/user-attachments/assets/28538e6f-ef3c-493b-aee2-0045695a0fb1" />


### 2.5 Create the Patroni Directories

**Run on:** `east_db`, `west_db`.

```bash
sudo install -d -o root -g postgres -m 0750 /etc/patroni
sudo install -d -o postgres -g postgres -m 0700 /var/lib/postgresql/patroni-main
sudo ls -ld /etc/patroni /var/lib/postgresql/patroni-main
```

<img width="1460" height="124" alt="image" src="https://github.com/user-attachments/assets/d3ccf3a5-d10e-4542-b909-17528da6cf3f" />


## 3. Configure PostgreSQL Based on Server Resources

The project's Python script detects the actual amount of RAM, CPU count, filesystem size, and storage type. It calculates a conservative starting configuration and writes it to `/etc/patroni/postgresql-tuning.conf`. Memory sizes do not have to be powers of two: a VM with 3 GiB of RAM is supported.

[PGTune](https://pgtune.leopard.in.ua/) is also available as a web calculator for PostgreSQL configuration recommendations. Its web interface requires the user to enter the server specifications and apply the generated settings; it does not discover our VMs or automate deployment by itself. This project therefore keeps the local Python script, which can run during manual installation or be invoked by Ansible without contacting an external website.

The generated settings are a starting point, not a guarantee of optimal performance for every workload. The script runs when invoked; it does not continuously monitor or retune PostgreSQL. After changing VM resources, rerun it, review the generated values, and apply changes through Patroni using the appropriate reload or restart procedure.

### 3.1 Copy the Script to the Database Nodes

Script location in the repository:

```text
02_Ansible/files/postgresql-autotune.py
```

**Run on the control machine from the repository root:**

```bash
scp -P 2222 02_Ansible/files/postgresql-autotune.py admin_aleksei@192.168.72.4:/tmp/
scp -P 2222 02_Ansible/files/postgresql-autotune.py admin_aleksei@192.168.73.4:/tmp/
```

Alternatively, open an editor on each database node and paste the complete script from the repository:

```bash
nano /tmp/postgresql-autotune.py
```

<img width="1546" height="881" alt="image" src="https://github.com/user-attachments/assets/2b0bad3e-bce3-4fa0-ad99-a49c08241d15" />

### 3.2 Install and Run the Script

**Run on:** `east_db`, `west_db`.

```bash
sudo install -o root -g root -m 0755 \
  /tmp/postgresql-autotune.py \
  /usr/local/sbin/project-postgresql-autotune
```

Preview the calculated settings without writing a file:

```bash
sudo /usr/local/sbin/project-postgresql-autotune --storage auto --dry-run
```

Generate the configuration file:

```bash
sudo /usr/local/sbin/project-postgresql-autotune \
  --storage auto \
  --data-dir /var/lib/postgresql/patroni-main \
  --output /etc/patroni/postgresql-tuning.conf
```

Check the output and confirm that the `postgres` user can read it:

```bash
sudo cat /etc/patroni/postgresql-tuning.conf
sudo -u postgres test -r /etc/patroni/postgresql-tuning.conf && echo "tuning file is readable"
```

If virtualization hides the actual storage type, explicitly use `ssd` or `hdd` instead of `auto`.

<img width="1546" height="881" alt="image" src="https://github.com/user-attachments/assets/9f7fb080-80b3-4ccb-a4eb-3e4458e84e7c" />


## 4. Configure Patroni

### 4.1 Generate Passwords

**Run once for each password on a trusted computer:**

```bash
openssl rand -hex 24
```

The cluster requires three passwords:

- PostgreSQL superuser password;
- replication user password;
- Patroni API password.

### 4.2 Set the Node Variables

**Run on `east_db`:**

```bash
NODE_NAME=east_db
NODE_IP=192.168.72.4
PG_MAJOR=$(ls -1 /usr/lib/postgresql | sort -V | tail -n 1)
```

**Run on `west_db`:**

```bash
NODE_NAME=west_db
NODE_IP=192.168.73.4
PG_MAJOR=$(ls -1 /usr/lib/postgresql | sort -V | tail -n 1)
```

<img width="1547" height="129" alt="image" src="https://github.com/user-attachments/assets/128c7c0c-e85e-43f2-9a40-0b2387af65c2" />


### 4.3 Enter Passwords Without Displaying Them

**Run on:** `east_db`, `west_db`.

Enter the same set of passwords on both nodes.

```bash
read -rsp "PostgreSQL postgres password: " PG_SUPER_PASS
echo
read -rsp "PostgreSQL replication password: " PG_REPLICATION_PASS
echo
read -rsp "Patroni API password: " PATRONI_API_PASS
echo
```

<img width="1494" height="549" alt="image" src="https://github.com/user-attachments/assets/a2de8d40-4125-4f63-a408-b3847dbcb8f2" />


### 4.4 Create the Patroni Configuration

**Run on:** `east_db`, `west_db`, after setting the variables for the corresponding node in the same shell session.

```bash
sudo tee /etc/patroni/config.yml >/dev/null <<EOF
scope: project-postgres
namespace: /service/
name: ${NODE_NAME}

restapi:
  listen: ${NODE_IP}:8008
  connect_address: ${NODE_IP}:8008
  authentication:
    username: patroni_admin
    password: "${PATRONI_API_PASS}"

ctl:
  authentication:
    username: patroni_admin
    password: "${PATRONI_API_PASS}"

etcd3:
  hosts:
    - "192.168.72.4:2379"
    - "192.168.73.4:2379"
    - "192.168.74.5:2379"

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    check_timeline: true
    synchronous_mode: false
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        wal_keep_size: 256MB
        max_slot_wal_keep_size: 2GB
        max_wal_senders: 10
        max_replication_slots: 10
  initdb:
    - encoding: UTF8
    - data-checksums

postgresql:
  listen: ${NODE_IP}:5432
  connect_address: ${NODE_IP}:5432
  data_dir: /var/lib/postgresql/patroni-main
  bin_dir: /usr/lib/postgresql/${PG_MAJOR}/bin
  pgpass: /var/lib/postgresql/.pgpass-patroni
  custom_conf: /etc/patroni/postgresql-tuning.conf

  authentication:
    superuser:
      username: postgres
      password: "${PG_SUPER_PASS}"
    replication:
      username: replicator
      password: "${PG_REPLICATION_PASS}"

  parameters:
    unix_socket_directories: /var/run/postgresql

  pg_hba:
    - local all all peer
    - host replication replicator 192.168.72.4/32 scram-sha-256
    - host replication replicator 192.168.73.4/32 scram-sha-256
    - host all postgres 192.168.72.4/32 scram-sha-256
    - host all postgres 192.168.73.4/32 scram-sha-256
    - host shopdb appuser 192.168.72.2/32 scram-sha-256
    - host shopdb appuser 192.168.73.2/32 scram-sha-256
    - host shopdb backup_reader 192.168.72.2/32 scram-sha-256
    - host shopdb backup_reader 192.168.73.2/32 scram-sha-256
    - host shopdb backup_reader 192.168.72.5/32 scram-sha-256
    - host shopdb backup_reader 192.168.73.5/32 scram-sha-256

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF
```

<img width="1494" height="549" alt="image" src="https://github.com/user-attachments/assets/a904fed9-3b7c-4ff2-a597-d9dab483023a" />


Set the file permissions and remove the password variables from the current shell:

```bash
sudo chown root:postgres /etc/patroni/config.yml
sudo chmod 0640 /etc/patroni/config.yml

unset PG_SUPER_PASS
unset PG_REPLICATION_PASS
unset PATRONI_API_PASS
```

<img width="1494" height="183" alt="image" src="https://github.com/user-attachments/assets/802a2815-9aa0-4400-ba5c-be85e13bb7d4" />


### 4.5 Create the Patroni Service

**Run on:** `east_db`, `west_db`.

```bash
sudo tee /etc/systemd/system/patroni.service >/dev/null <<'EOF'
[Unit]
Description=Project Patroni
After=network-online.target etcd.service
Wants=network-online.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/bin/patroni /etc/patroni/config.yml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```

<img width="1494" height="406" alt="image" src="https://github.com/user-attachments/assets/2540e270-458f-4713-8713-309d72a5bd71" />


Validate the unit file and enable the service at boot:

```bash
sudo systemd-analyze verify /etc/systemd/system/patroni.service
sudo systemctl daemon-reload
sudo systemctl enable patroni
```

<img width="1494" height="118" alt="image" src="https://github.com/user-attachments/assets/403f5f34-d821-4222-a09b-45cfd0d7d1ae" />


## 5. Start the Patroni Cluster

### 5.1 Start the First Node

**Run only on:** `east_db`.

```bash
sudo systemctl start patroni
sudo systemctl status patroni --no-pager -l
```

Check the newly initialized cluster:

```bash
sudo -u postgres patronictl -c /etc/patroni/config.yml list
```

The first node should take the `Leader` role.

<img width="767" height="124" alt="image" src="https://github.com/user-attachments/assets/631335df-8de8-40e7-abf3-8bd960a2c2fd" />


### 5.2 Start the Second Node

**Run only on:** `west_db`.

```bash
sudo systemctl start patroni
sudo systemctl status patroni --no-pager -l
```

<img width="1352" height="786" alt="image" src="https://github.com/user-attachments/assets/e9f96945-d354-4937-be38-c11616eef80b" />


Check the cluster from either database node:

```bash
sudo -u postgres patronictl -c /etc/patroni/config.yml list
```

Expected result: one node is the `Leader` and the other is a `Replica`.

## 6. Create the Database and Users

Run all commands in this section only on the current `Leader`. Identify the leader with:

```bash
sudo -u postgres patronictl -c /etc/patroni/config.yml list
```

### 6.1 Create the Application User

**Run on:** the current `Leader`.

```bash
read -rsp "appuser password: " APP_PASSWORD
echo
read -rsp "backup_reader password: " BACKUP_PASSWORD
echo

sudo -u postgres psql \
  -h /var/run/postgresql \
  -U postgres \
  -d postgres \
  -v ON_ERROR_STOP=1 \
  -v app_user=appuser \
  -v app_password="$APP_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_user', :'app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user') \gexec

SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'app_user', :'app_password') \gexec
SQL
```

<img width="957" height="534" alt="image" src="https://github.com/user-attachments/assets/3011b253-7f4b-45c7-8237-92d70941fb23" />


### 6.2 Create the shopdb Database and products Table

**Run on:** the current `Leader`.

```bash
sudo -u postgres psql \
  -h /var/run/postgresql \
  -U postgres \
  -d postgres \
  -v ON_ERROR_STOP=1 \
  -v db_name=shopdb \
  -v app_user=appuser <<'SQL'
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'app_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name') \gexec

SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'app_user') \gexec

\connect :db_name

BEGIN;

CREATE TABLE IF NOT EXISTS public.products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    image_key VARCHAR(512)
);

SELECT format('ALTER TABLE public.products OWNER TO %I', :'app_user') \gexec
SELECT format('ALTER SEQUENCE public.products_id_seq OWNER TO %I', :'app_user') \gexec
SELECT format('GRANT USAGE, CREATE ON SCHEMA public TO %I', :'app_user') \gexec
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.products TO %I', :'app_user') \gexec
SELECT format('GRANT USAGE, SELECT, UPDATE ON SEQUENCE public.products_id_seq TO %I', :'app_user') \gexec

COMMIT;
SQL
```

<img width="957" height="717" alt="image" src="https://github.com/user-attachments/assets/6ce29e3e-6416-436e-9a0e-cd79c4e8b867" />


### 6.3 Create the Backup User

**Run on:** the current `Leader`.

```bash
sudo -u postgres psql \
  -h /var/run/postgresql \
  -U postgres \
  -d postgres \
  -v ON_ERROR_STOP=1 \
  -v backup_user=backup_reader \
  -v backup_password="$BACKUP_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN', :'backup_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'backup_user') \gexec

SELECT format(
  'ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L',
  :'backup_user',
  :'backup_password'
) \gexec

SELECT format('GRANT pg_read_all_data TO %I', :'backup_user') \gexec
SELECT format('GRANT CONNECT ON DATABASE shopdb TO %I', :'backup_user') \gexec
SQL

unset APP_PASSWORD
unset BACKUP_PASSWORD
```

<img width="957" height="282" alt="image" src="https://github.com/user-attachments/assets/5c3e4476-c579-4435-9ddb-88b2767c6918" />


## 7. Verify the Database and Replication

### 7.1 Verify the Table

**Run on:** the current `Leader`.

```bash
sudo -u postgres psql -h /var/run/postgresql -d shopdb -c "\dt"
sudo -u postgres psql -h /var/run/postgresql -d shopdb -c "\d public.products"
```

Insert a test record:

```bash
sudo -u postgres psql \
  -h /var/run/postgresql \
  -d shopdb \
  -c "INSERT INTO products(name, price, stock) VALUES ('Test product', 9.99, 10);"
```

Check the data:

```bash
sudo -u postgres psql -h /var/run/postgresql -d shopdb -c "SELECT * FROM products;"
```

<img width="1490" height="467" alt="image" src="https://github.com/user-attachments/assets/e6d383ad-ae2f-4d68-a2c5-66c2ec4a22b6" />


### 7.2 Check Patroni Cluster Status

**Run on:** `east_db` or `west_db`.

```bash
sudo -u postgres patronictl -c /etc/patroni/config.yml list
```

### 7.3 Verify Streaming Replication

**Run on:** the current `Leader`.

```bash
sudo -u postgres psql \
  -h /var/run/postgresql \
  -d postgres \
  -c "SELECT application_name, client_addr, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"
```

The `state` column should show `streaming`. With asynchronous replication, the `sync_state` column should show `async`.

<img width="955" height="172" alt="image" src="https://github.com/user-attachments/assets/39ca1893-f85b-4545-a856-14b6bfdb3cdc" />


### 7.4 Recheck etcd Health

**Run on any one etcd node.**

```bash
export ETCDCTL_API=3

etcdctl \
  --endpoints=http://192.168.72.4:2379,http://192.168.73.4:2379,http://192.168.74.5:2379 \
  endpoint health
```

All three endpoints should report `is healthy`.

<img width="1274" height="220" alt="image" src="https://github.com/user-attachments/assets/ea37b9b1-23d3-4e50-b18d-44b316e218ff" />


## 8. Test a Leader Switchover

Perform this test in the lab or after taking a backup.

Display the current cluster state:

```bash
sudo -u postgres patronictl -c /etc/patroni/config.yml list
```

Switch the leader role to the other node:

```bash
sudo -u postgres patronictl -c /etc/patroni/config.yml switchover
```

After the switchover, verify the node roles and confirm that the test record is still available:

```bash
sudo -u postgres patronictl -c /etc/patroni/config.yml list
sudo -u postgres psql -h /var/run/postgresql -d shopdb -c "SELECT * FROM products;"
```

## 9. Troubleshooting Commands

Check service status:

```bash
sudo systemctl status etcd --no-pager -l
sudo systemctl status patroni --no-pager -l
```

View recent logs:

```bash
sudo journalctl -u etcd -b -n 100 --no-pager -l
sudo journalctl -u patroni -b -n 100 --no-pager -l
```

Check listening ports:

```bash
sudo ss -lntp | grep -E ':2379|:2380|:5432|:8008'
```

Check that the generated tuning file exists and is readable:

```bash
sudo test -f /etc/patroni/postgresql-tuning.conf
sudo -u postgres test -r /etc/patroni/postgresql-tuning.conf
```

If Patroni reports `Failed to bootstrap cluster`, inspect the full journal first. An error mentioning `could not open configuration file` and `/etc/patroni/postgresql-tuning.conf` indicates a problem accessing the tuning file. Confirm that the script created it and that the `postgres` user can read it before retrying startup.

