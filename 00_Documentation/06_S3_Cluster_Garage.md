
# Garage S3 Storage Cluster Deployment
[![Garage](https://img.shields.io/badge/Garage-FF6B35?style=for-the-badge&logoColor=white)](https://garagehq.deuxfleurs.fr/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](https://ubuntu.com/)
## Overview

This document describes the manual deployment of a three-node, S3-compatible storage cluster based on [Garage](https://garagehq.deuxfleurs.fr/).

The cluster is distributed across three infrastructure zones:

| Node | Zone | IP address | Purpose |
|---|---|---:|---|
| `east-storage` | East | `192.168.72.5` | S3 storage node in the East branch |
| `west-storage` | West | `192.168.73.5` | S3 storage node in the West branch |
| `cloud-s3` | Cloud | `192.168.74.6` | Third storage node and quorum participant |

The storage system has two levels of redundancy:

1. **Local disk redundancy:** each storage VM uses RAID1, which protects data against the failure of one virtual disk.
2. **Distributed storage redundancy:** Garage replicates objects between the East, West, and Cloud zones.

With a replication factor of `3`, every object is stored on all three Garage nodes. Losing one node therefore does not remove the remaining copies of the data. The affected node can later rejoin the cluster and synchronize again.

The storage has two main purposes:

- Storing application objects, such as product images, through an S3-compatible API.
- Storing monitoring stack logs.
- Providing separate local storage for database dumps, logs, and Restic repositories.

Each VM uses two RAID1 arrays:

| Array | Mount point | Purpose |
|---|---|---|
| `/dev/md0` | `/srv/storage` | Garage object data |
| `/dev/md1` | `/srv/backup` | Database, log, and infrastructure backups |

The Garage cluster does not have a dedicated primary node or controller. Although the initial cluster connection commands can be executed from `cloud-s3`, all three nodes remain equal cluster members.

## Important Security Notes

The following values must never be committed to a public Git repository or displayed in unredacted screenshots:

- `rpc_secret`
- `admin_token`
- `metrics_token`
- S3 access keys
- S3 secret keys

In this project, these values should be stored in Ansible Vault and inserted during automated deployment.

Garage node IDs are node identifiers rather than authentication credentials. However, they are replaced with placeholders in this guide to keep the documentation portable and to avoid publishing unnecessary infrastructure details.

## Prerequisites

The following packages must be available on every storage VM:

```bash
sudo apt update
sudo apt install -y mdadm curl
```

Each VM must have four additional disks:

- `garage1`
- `garage2`
- `backup1`
- `backup2`

The examples use stable `/dev/disk/by-id/` paths instead of device names such as `/dev/vdb`, because ordinary device names may change after a reboot.

---

## 1. Verify the Attached Disks

Log in to every storage VM and verify that the additional disks are available:

<img width="940" height="592" alt="image" src="https://github.com/user-attachments/assets/084e08c9-b3c3-4a34-9203-bf32693d973c" />


```bash
lsblk
blkid
```

---

## 2. Create the RAID1 Arrays

Create the RAID1 array used by Garage:

```bash
sudo mdadm --create /dev/md0 --metadata=1.2 --level=1 --raid-devices=2 --name=garage --run --force /dev/disk/by-id/virtio-garage1 /dev/disk/by-id/virtio-garage2
```

Create a separate RAID1 array for backups:

```bash
sudo mdadm --create /dev/md1 --metadata=1.2 --level=1 --raid-devices=2 --name=backup --run --force /dev/disk/by-id/virtio-backup1 /dev/disk/by-id/virtio-backup2
```

The `--force` option was used because these were newly created, empty lab disks. It should not be used on disks containing existing data.

<img width="940" height="579" alt="image" src="https://github.com/user-attachments/assets/afab94de-783b-4e19-934c-697a1023b365" />

---

## 3. Verify the RAID Status

Check the synchronization state:

```bash
cat /proc/mdstat
```

Display detailed information about both arrays:

```bash
sudo mdadm --detail /dev/md0
sudo mdadm --detail /dev/md1
```

Both arrays should report two active devices. RAID synchronization may continue in the background after the arrays have been created.

<img width="940" height="588" alt="image" src="https://github.com/user-attachments/assets/e5ad9d4f-9086-4f83-adf8-4fe316dc52a1" />


---

## 4. Create the Filesystems

Create an ext4 filesystem for Garage:

```bash
sudo mkfs.ext4 -L garage /dev/md0
```

Create an ext4 filesystem for backups:

```bash
sudo mkfs.ext4 -L backup /dev/md1
```

Create the mount points:

```bash
sudo mkdir -p /srv/storage
sudo mkdir -p /srv/backup
```

<img width="940" height="598" alt="image" src="https://github.com/user-attachments/assets/4f9ddb36-35ee-4a99-9e15-8aac92f9d46c" />

<img width="940" height="598" alt="image" src="https://github.com/user-attachments/assets/6f9fb9a6-146e-4d32-aeae-a00c52176192" />



---

## 5. Configure Persistent Mounts

Read the filesystem UUIDs and add the mount definitions to `/etc/fstab`.

For Garage storage:

```bash
GARAGE_UUID=$(sudo blkid -s UUID -o value /dev/md0)

grep -qE '[[:space:]]/srv/storage[[:space:]]' /etc/fstab || \
  echo "UUID=$GARAGE_UUID /srv/storage ext4 defaults,nofail 0 2" | \
  sudo tee -a /etc/fstab
```

For backup storage:

```bash
BACKUP_UUID=$(sudo blkid -s UUID -o value /dev/md1)

grep -qE '[[:space:]]/srv/backup[[:space:]]' /etc/fstab || \
  echo "UUID=$BACKUP_UUID /srv/backup ext4 defaults,nofail 0 2" | \
  sudo tee -a /etc/fstab
```

Using UUIDs prevents mount failures if Linux assigns different `/dev/md*` or virtual disk names after a reboot.

Reload the systemd configuration and mount the filesystems:

```bash
sudo systemctl daemon-reload
sudo mount -a
```

Verify the result:

```bash
findmnt /srv/storage
findmnt /srv/backup
df -h /srv/storage /srv/backup
```

<img width="940" height="485" alt="image" src="https://github.com/user-attachments/assets/cd5b0204-862b-47b4-9aae-57af95846e60" />


---

## 6. Save the RAID Configuration

Add both arrays to `/etc/mdadm/mdadm.conf`:

```bash
sudo sh -c 'printf "\n# BEGIN PROJECT STORAGE ARRAYS\n" >> /etc/mdadm/mdadm.conf; \
mdadm --detail --brief /dev/md0 >> /etc/mdadm/mdadm.conf; \
mdadm --detail --brief /dev/md1 >> /etc/mdadm/mdadm.conf; \
printf "# END PROJECT STORAGE ARRAYS\n" >> /etc/mdadm/mdadm.conf'
```

Update the initial RAM filesystem so that the arrays can be assembled during boot:

```bash
sudo update-initramfs -u
```

Run the configuration command only once to avoid duplicate entries in `mdadm.conf`.

<img width="940" height="708" alt="image" src="https://github.com/user-attachments/assets/40e19eef-d94d-40b0-9729-f00e9bf30265" />


---

# Garage Installation

The following steps must be completed on all three Garage nodes.

## 7. Create the Garage System User

Create a dedicated system account:

```bash
sudo groupadd --system garage

sudo useradd \
  --system \
  --gid garage \
  --no-create-home \
  --shell /usr/sbin/nologin \
  garage
```

Create the metadata, object data, and snapshot directories:

```bash
sudo mkdir -p /var/lib/garage/meta
sudo mkdir -p /srv/storage/garage/data
sudo mkdir -p /srv/storage/garage/snapshots
```

Set ownership and permissions:

```bash
sudo chown -R garage:garage /var/lib/garage
sudo chown -R garage:garage /srv/storage/garage

sudo chmod -R 750 /var/lib/garage
sudo chmod -R 750 /srv/storage/garage
```

The Garage service runs without an interactive login shell and only receives access to the directories that it needs.

<img width="940" height="708" alt="image" src="https://github.com/user-attachments/assets/e58c2c08-c01b-404c-a144-9b7fa094308d" />


---

## 8. Install Garage

This deployment was tested with Garage version `2.4.1` on `x86_64` Linux:

```bash
curl -fL \
  https://garagehq.deuxfleurs.fr/_releases/v2.4.1/x86_64-unknown-linux-musl/garage \
  -o /tmp/garage
```

Install the binary:

```bash
sudo install \
  -o root \
  -g root \
  -m 0755 \
  /tmp/garage \
  /usr/local/bin/garage
```

Verify the installed version:

```bash
garage --version
```

<img width="940" height="708" alt="image" src="https://github.com/user-attachments/assets/1d4a3daa-8d67-431b-abcd-ed3908e6dc8e" />


---

## 9. Configure Garage

Create the configuration file:

```bash
sudo nano /etc/garage.toml
```

Use the following configuration:

```toml
metadata_dir = "/var/lib/garage/meta"
data_dir = "/srv/storage/garage/data"
metadata_snapshots_dir = "/srv/storage/garage/snapshots"
metadata_auto_snapshot_interval = "6h"

db_engine = "lmdb"

replication_factor = 3
consistency_mode = "consistent"
compression_level = 1

rpc_bind_addr = "0.0.0.0:3901"
rpc_public_addr = "<NODE_IP>:3901"
rpc_secret = "<RPC_SECRET>"

[s3_api]
s3_region = "garage"
api_bind_addr = "0.0.0.0:3900"
advertise_endpoint = "http://<NODE_IP>:3900"
advertise_path_style = true

[admin]
api_bind_addr = "0.0.0.0:3903"
admin_token = "<ADMIN_TOKEN>"
metrics_token = "<METRICS_TOKEN>"
metrics_require_token = true
```

Replace `<NODE_IP>` with the address of the current node:

| Node | `NODE_IP` |
|---|---:|
| `east-storage` | `192.168.72.5` |
| `west-storage` | `192.168.73.5` |
| `cloud-s3` | `192.168.74.6` |

The same `rpc_secret` must be configured on all three nodes. This secret authenticates internal Garage RPC communication.

The configuration exposes the following services:

| Port | Purpose |
|---:|---|
| `3900/tcp` | S3-compatible API |
| `3901/tcp` | Internal Garage RPC communication |
| `3903/tcp` | Administration and metrics API |

Access to these ports should be restricted by the firewall according to the infrastructure network design.

Set secure ownership and permissions:

```bash
sudo chown root:garage /etc/garage.toml
sudo chmod 640 /etc/garage.toml
```

Verify the result:

```bash
sudo ls -l /etc/garage.toml
```

<img width="940" height="621" alt="image" src="https://github.com/user-attachments/assets/9d74fec1-f0fe-4689-9610-56540ca99e22" />

<img width="940" height="669" alt="image" src="https://github.com/user-attachments/assets/db63bb4a-1611-4943-a4db-3e55623fbfcd" />

---

## 10. Create the Systemd Service

Create the service file:

```bash
sudo nano /etc/systemd/system/garage.service
```

Add the following configuration:

```ini
[Unit]
Description=Garage distributed S3 object store
Wants=network-online.target
After=network-online.target
RequiresMountsFor=/srv/storage

[Service]
Type=simple
User=garage
Group=garage

Environment=GARAGE_CONFIG_FILE=/etc/garage.toml
Environment=RUST_LOG=garage=info
Environment=RUST_BACKTRACE=1

ExecStart=/usr/local/bin/garage server

Restart=on-failure
RestartSec=5s
LimitNOFILE=42000

NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/var/lib/garage /srv/storage/garage

[Install]
WantedBy=multi-user.target
```

The service includes several systemd hardening options. In particular, `ProtectSystem=strict` prevents the service from modifying the operating system, while `ReadWritePaths` explicitly allows access to the Garage data directories.

Reload systemd and start Garage:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now garage
```

Check the service:

```bash
sudo systemctl status garage --no-pager
```

<img width="940" height="660" alt="image" src="https://github.com/user-attachments/assets/0c9d3191-7823-46b9-9699-9cef2b17d57f" />

<img width="940" height="621" alt="image" src="https://github.com/user-attachments/assets/906644bd-8d96-439c-93d9-deb3c0d2496f" />

---

# Cluster Configuration

## 11. Retrieve the Node IDs

Run the following command on every node:

```bash
sudo garage node id
```

Record the node ID and RPC address returned by each machine:

```text
<EAST_NODE_ID>@192.168.72.5:3901
<WEST_NODE_ID>@192.168.73.5:3901
<CLOUD_NODE_ID>@192.168.74.6:3901
```

The actual node IDs have been replaced with placeholders in this documentation.

<!-- Add screenshot here: garage node id output with identifiers redacted if required -->

---

## 12. Connect the Nodes

From one node, for example `cloud-s3`, connect to the East and West nodes:

```bash
sudo garage node connect \
  <EAST_NODE_ID>@192.168.72.5:3901

sudo garage node connect \
  <WEST_NODE_ID>@192.168.73.5:3901
```

Garage uses peer-to-peer cluster communication. Running these commands from `cloud-s3` does not make it a master or controller; it only introduces the nodes to each other.

Verify cluster membership:

```bash
sudo garage status
```

Before roles are assigned, the nodes may appear with the status `NO ROLE ASSIGNED`.

<img width="940" height="629" alt="image" src="https://github.com/user-attachments/assets/3c6c3411-3c75-44e0-bf0a-eeeaa65e6e46" />


---

## 13. Assign Storage Roles

Assign each node to its geographical zone.

East node:

```bash
sudo garage layout assign <EAST_NODE_ID> \
  --zone east \
  --capacity 12G \
  --tag east_storage
```

West node:

```bash
sudo garage layout assign <WEST_NODE_ID> \
  --zone west \
  --capacity 12G \
  --tag west_storage
```

Cloud node:

```bash
sudo garage layout assign <CLOUD_NODE_ID> \
  --zone cloud \
  --capacity 12G \
  --tag cloud_storage
```

The zone names tell Garage that the nodes are located in separate failure domains. The configured capacity is lower than the total filesystem size to leave operational space for metadata and filesystem overhead.

Review the proposed layout:

```bash
sudo garage layout show
```

Apply the layout using the version displayed by Garage:

```bash
sudo garage layout apply --version <NEXT_LAYOUT_VERSION>
```

In the captured deployment, version `2` was used because an earlier layout attempt had already created version `1`. A fresh deployment may use a different version.

<img width="940" height="525" alt="image" src="https://github.com/user-attachments/assets/b6b86b5e-5168-4653-b45d-e40d02d4b44e" />


---

## 14. Verify Cluster Health

Check the cluster status:

```bash
sudo garage status
```

Query the health API:

```bash
sudo garage json-api GetClusterHealth
```

A healthy three-node cluster should report:

- Three connected nodes
- Three known nodes
- Three active storage nodes
- All partitions available
- Cluster status `healthy`

With a replication factor of `3`, the effective storage capacity is approximately the capacity assigned to one node because every object is stored on all three nodes.

<img width="940" height="329" alt="image" src="https://github.com/user-attachments/assets/cc11cf32-b6da-4e52-a845-ab166a523521" />



---

# S3 Bucket Configuration

## 15. Create the Application Bucket

Create a bucket for product images:

```bash
sudo garage bucket create product-images
```

Display bucket information:

```bash
sudo garage bucket info product-images
```

At this stage, the bucket exists but no application key has permission to access it.

<img width="940" height="525" alt="image" src="https://github.com/user-attachments/assets/d9428f0c-cb96-40b8-9d07-9f194fdd27bd" />


---

## 16. Import the Application Key

Import the access key and secret key used by the web application:

```bash
sudo garage key import \
  --yes \
  -n shop-web \
  "<ACCESS_KEY>" \
  "<SECRET_KEY>"
```

Grant the key read and write access to the bucket:

```bash
sudo garage bucket allow \
  --read \
  --write \
  product-images \
  --key "<ACCESS_KEY>"
```

Verify the assigned permissions:

```bash
sudo garage bucket info product-images
```

<img width="940" height="525" alt="image" src="https://github.com/user-attachments/assets/aae0c8ff-bee6-42e0-9d06-8a14f8d658e8" />


---

## 17. Review the Current Layout and Buckets

Before changing the bucket configuration, review the active Garage layout and the existing buckets:

```bash
sudo garage layout show
sudo garage bucket list
```

This confirms that all three storage nodes still have active roles and that the `product-images` bucket already exists.

<img width="715" height="240" alt="image" src="https://github.com/user-attachments/assets/58c40658-63bb-4b08-a256-9db317551129" />


---

## 18. Set the Product Images Quota

Limit the `product-images` bucket to `2 GiB`:

```bash
sudo garage bucket set-quotas --max-size 2GiB product-images
```

The quota limits the logical amount of data that can be stored in the bucket. Because Garage uses a replication factor of `3`, the objects are still replicated to all three storage nodes.

Verify the bucket information and the assigned application key:

```bash
sudo garage bucket info product-images
```

The expected result is a maximum size of `2.0 GiB` and read/write access for the `shop-web` key.

<img width="715" height="348" alt="image" src="https://github.com/user-attachments/assets/44e74aee-a6b9-45a0-ac18-5a5058fb6d08" />


---

## 19. Create the Monitoring Logs Bucket

Create a separate bucket for logs produced by the monitoring stack:

```bash
sudo garage bucket create monitoring-logs
```

Set an `8 GiB` quota for the new bucket:

```bash
sudo garage bucket set-quotas --max-size 8GiB monitoring-logs
```

Keeping logs in a separate bucket allows them to use their own credentials, permissions, quota, retention policy, and backup workflow without giving the monitoring services access to application images.

Verify the result:

```bash
sudo garage bucket info monitoring-logs
```

<img width="715" height="582" alt="image" src="https://github.com/user-attachments/assets/6ff6e891-358c-428e-b0c2-ebf15cc34bb5" />


---

## 20. Import the Loki Storage Key

Import the access key and secret key used by Loki:

```bash
sudo garage key import \
  --yes \
  -n loki-storage \
  "<GARAGE_LOKI_ACCESS_KEY>" \
  "<GARAGE_LOKI_SECRET_KEY>"
```

Replace the placeholders with the values stored in Ansible Vault. The example uses placeholders rather than shell variables, so the values should be pasted directly without a leading `$`.

Grant the key read and write access only to the monitoring bucket:

```bash
sudo garage bucket allow \
  --read \
  --write \
  monitoring-logs \
  --key "<GARAGE_LOKI_ACCESS_KEY>"
```

Verify the permissions:

```bash
sudo garage bucket info monitoring-logs
```

The `loki-storage` key should have read and write access to `monitoring-logs` and no permissions for `product-images`.

<img width="1403" height="594" alt="image" src="https://github.com/user-attachments/assets/b291ca3e-7b00-4e68-adf8-d12320beb4ec" />

---

## 21. Final Validation

Verify that the service is active:

```bash
sudo systemctl is-active garage
```

Check the cluster members:

```bash
sudo garage status
```

Check the overall cluster health:

```bash
sudo garage json-api GetClusterHealth
```

Check both buckets and their quotas:

```bash
sudo garage bucket list
sudo garage bucket info product-images
sudo garage bucket info monitoring-logs
```

The expected result is:

- Garage is active on all three nodes.
- All three nodes are connected.
- All partitions are available.
- The cluster reports a healthy status.
- The `product-images` bucket has a `2 GiB` quota.
- The `shop-web` key has read and write access to the bucket.
- The `monitoring-logs` bucket has an `8 GiB` quota.
- The `loki-storage` key has read and write access only to `monitoring-logs`.

<img width="607" height="274" alt="image" src="https://github.com/user-attachments/assets/6c8bdd9c-91a5-499e-a418-487fc3c8f8fc" />



---

## Accessing the S3 Service

The S3-compatible API is available on port `3900`:

```text
http://192.168.72.5:3900
http://192.168.73.5:3900
http://192.168.74.6:3900
```

Garage does not provide an ordinary graphical file browser. The S3 API should be accessed through:

- The web application
- AWS CLI
- `s3cmd`
- `rclone`
- Another S3-compatible client

Opening the endpoint directly in a web browser may return:

```xml
<Code>AccessDenied</Code>
<Message>Forbidden: Garage does not support anonymous access yet</Message>
```

This response is expected. It confirms that the S3 API is reachable but rejects unauthenticated access.

## Result

The infrastructure now has a distributed, three-zone S3-compatible storage cluster with:

- Local RAID1 protection on every storage VM
- Cross-zone object replication
- Separate East, West, and Cloud failure domains
- Authenticated S3 access
- A `product-images` bucket with a `2 GiB` quota and a dedicated `shop-web` key
- A separate `monitoring-logs` bucket with an `8 GiB` quota and a dedicated `loki-storage` key
- Isolated permissions between application images and monitoring logs
- A separate RAID1 volume prepared for database and log backups
- Systemd service isolation and automatic restart
- Health and metrics endpoints for future monitoring integration
