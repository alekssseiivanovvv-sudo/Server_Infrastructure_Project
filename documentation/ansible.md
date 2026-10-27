# Ansible Automation

## Overview

Ansible is the main configuration-management tool used in this project. All
playbooks are launched from the dedicated **automation-node**, which acts as the
Ansible control node. It stores the project repository, inventory, Ansible
configuration, SSH key and encrypted Vault variables.

The automation-node does not host the production services. It performs two
types of work:

- runs local orchestration tasks, such as Terraform and certificate generation;
- connects to the hypervisors and virtual machines over SSH and applies their
  configuration remotely.

The managed infrastructure includes two KVM/libvirt hypervisors, three routers,
application and load-balancer nodes, a PostgreSQL/Patroni cluster, Garage S3
storage, the monitoring stack, backup nodes and an external DNS node.

## Control-node configuration

The project uses the following defaults from `ansible/ansible.cfg`:

| Setting | Value | Purpose |
|---|---|---|
| Inventory | `inventory` | Defines all managed hosts and functional host groups |
| Remote user | `ansible_admin` | Dedicated service account used by Ansible |
| SSH private key | `~/.ssh/ansible` | Authentication key used by the automation-node |
| Host-key checking | Disabled | Allows newly recreated Terraform VMs to be reached immediately |
| Vault editor | `nano` | Editor used by `ansible-vault edit` |

Sensitive values are stored in the encrypted
`group_vars/group/all/vault.yml` file. They include account password hashes,
service passwords, S3 credentials, SSH ports, monitoring credentials and other
secrets. Secrets are never stored directly in playbooks or templates.

Shared non-secret settings, such as the PostgreSQL version, project subnets,
DNS domain and internal router addresses, are stored in
`group_vars/all/project.yml`.

## Running playbooks from automation-node

Run Ansible commands from the `ansible` directory so that the local
`ansible.cfg`, inventory and relative paths are used:

```bash
cd ~/Server_Infrastructure_Project/ansible
```

Check the inventory before deployment:

```bash
ansible-inventory --graph --ask-vault-pass
```

Run an individual playbook:

```bash
ansible-playbook 03_FIREWALL_DNS.yml --ask-vault-pass
```

Limit a normal playbook to one host only when the playbook supports partial
execution:

```bash
ansible-playbook 10_MONITORING_agents.yml --limit east_web --ask-vault-pass
```

## Deployment order

| Order | Playbook | Main target | Purpose |
|---:|---|---|---|
| 00 | [`00_HYPERVISOR_bootsrap.yml`](../ansible/00_HYPERVISOR_bootsrap.yml) | Hypervisors | Prepare the Ansible account, SSH and libvirt storage access |
| 01 | [`01_TERRAFORM.yml`](../ansible/01_TERRAFORM.yml) | automation-node | Create or update networks and virtual machines with Terraform |
| 02 | [`02_VM_initial_boorstrap.yml`](../ansible/02_VM_initial_boorstrap.yml) | Hypervisors and infrastructure VMs | Create administrator accounts and enforce SSH key authentication |
| 03 | [`03_FIREWALL_DNS.yml`](../ansible/03_FIREWALL_DNS.yml) | Routers and servers | Configure routing security, internal DNS and host firewalls |
| 04 | [`04_S3_STORAGE_service.yml`](../ansible/04_S3_STORAGE_service.yml) | Garage nodes | Create storage RAID arrays and deploy the Garage S3 cluster |
| 05 | [`05_DB_cluster.yml`](../ansible/05_DB_cluster.yml) | etcd and PostgreSQL nodes | Deploy etcd, Patroni, PostgreSQL and the application database |
| 06 | [`06_WEB_HAPROXY_DNS_service.yml`](../ansible/06_WEB_HAPROXY_DNS_service.yml) | Web, HAProxy and external DNS nodes | Deploy the web application, load balancers and DNS failover |
| 07 | [`07_TLS_certificates.yml`](../ansible/07_TLS_certificates.yml) | automation-node and HAProxy nodes | Create the internal CA and enable TLS on HAProxy |
| 08 | [`08_install_ca_firefox.yml`](../ansible/08_install_ca_firefox.yml) | Hypervisors | Trust the internal CA in the operating system and Firefox profiles |
| 09 | [`09_MONITORING_server.yml`](../ansible/09_MONITORING_server.yml) | Monitoring server | Install Prometheus, Loki, Grafana, dashboards and alerting |
| 10 | [`10_MONITORING_agents.yml`](../ansible/10_MONITORING_agents.yml) | Managed nodes | Install Alloy and optional Node Exporter agents |
| 11 | [`11_BACKUP_service.yml`](../ansible/11_BACKUP_service.yml) | Branch storage nodes | Configure scheduled S3 and PostgreSQL backups with Restic |

The playbooks are idempotent and can normally be run again after configuration
changes. The order matters during the first deployment because later services
depend on networks, accounts, DNS, storage or databases created earlier.

---

## Playbook details

### 00 — Hypervisor bootstrap

- **File:** [`00_HYPERVISOR_bootsrap.yml`](../ansible/00_HYPERVISOR_bootsrap.yml)
- **Targets:** `hypervisor_hosts`
- **Execution mode:** one hypervisor at a time with `serial: 1`

This playbook prepares both physical hosts for management from automation-node.

Actions:

- creates the `ansible_admin` automation account;
- installs the automation-node public key for `ansible_admin`;
- configures passwordless `sudo` for the automation account;
- resets the initial SSH connection and verifies public-key access;
- verifies that passwordless privilege escalation works;
- configures and validates the SSH daemon settings;
- checks that `/var/lib/libvirt/images/templates` exists and contains base
  images;
- sets ownership and permissions for template directories and image files;
- grants the `libvirt-qemu` account read access to base images and read/write
  access to Terraform-managed VM disks;
- adds the required local AppArmor rules and reloads AppArmor;
- verifies access to every template image as the `libvirt-qemu` user.

The initial run can use the current hypervisor account before `ansible_admin`
is ready:

```bash
ansible-playbook 00_HYPERVISOR_bootsrap.yml --limit host_1 -e bootstrap_user=<existing-user> --ask-pass --ask-become-pass --ask-vault-pass
```

Run the same command for `host_2` with its existing bootstrap user.

### 01 — Terraform infrastructure deployment

- **File:** [`01_TERRAFORM.yml`](../ansible/01_TERRAFORM.yml)
- **Target:** `automation_nodes`
- **Execution mode:** local on automation-node

Actions:

- uses the Terraform project from the repository's `terraform` directory;
- enables non-interactive Terraform automation mode;
- creates a saved Terraform plan with a state-lock timeout;
- distinguishes between an unchanged plan and a plan containing changes;
- applies the saved plan only when changes are present;
- reports when the infrastructure is already up to date;
- removes the temporary `ansible.tfplan` file even if the operation fails.

Terraform must already be installed and the project must have been initialized
with `terraform init` on automation-node.

### 02 — Initial VM and administrator bootstrap

- **File:** [`02_VM_initial_boorstrap.yml`](../ansible/02_VM_initial_boorstrap.yml)
- **Targets:** `hypervisor_hosts`, `automation_nodes` and `infrastructure`

Actions:

- selects the correct local hardware administrator for each hypervisor from
  Ansible Vault;
- creates the local administrator with `sudo` or `wheel` membership;
- generates one Ed25519 administrator key pair on each hypervisor;
- adds the administrator to the hypervisor SSH `AllowUsers` list;
- stores the public keys temporarily for distribution to infrastructure VMs;
- removes obsolete SSH host keys for Terraform-recreated VMs from the
  hypervisors and automation-node;
- creates `admin_aleksei` and `admin_ilja` on all infrastructure machines;
- adds both administrators to `sudo` on Ubuntu or `wheel` on Alpine;
- installs the public keys generated on `host_1` and `host_2` for the matching
  human administrators;
- creates `system_admin` as a console-only emergency administrator;
- removes SSH authorized keys from `system_admin`;
- disables password and keyboard-interactive SSH authentication;
- permits SSH only for `ansible_admin`, `admin_aleksei` and `admin_ilja`;
- validates the final SSH configuration before reloading the SSH service.

Human administrators use SSH keys to log in. Their Vault-managed local
passwords are used only for `sudo`. The `system_admin` account is deliberately
excluded from remote SSH access.

### 03 — Firewall and internal DNS

- **File:** [`03_FIREWALL_DNS.yml`](../ansible/03_FIREWALL_DNS.yml)
- **Targets:** `routers`, `infrastructure:!routers` and `linux_servers`

Actions on routers:

- installs nftables and enables IPv4 forwarding;
- deploys a default-deny router firewall;
- permits router SSH only through the Tailscale interface;
- permits DNS requests from the router's local branch subnet;
- permits LAN-to-WAN and LAN-to-Tailscale forwarding;
- permits Tailscale-to-LAN forwarding for routed project traffic;
- applies TCP MSS adjustment for traffic crossing the VPN;
- configures source NAT masquerading only on the WAN interface;
- installs dnsmasq and creates inventory-based `project.local` records;
- creates friendly aliases for the shop, load balancers, monitoring, quorum
  and S3 services;
- forwards non-project queries to the configured upstream DNS servers;
- verifies local name resolution after the configuration is applied.

Actions on servers:

- selects the local east, west or cloud router as the DNS server;
- configures `systemd-resolved` on Ubuntu and resolver settings on Alpine;
- verifies resolution of internal project records;
- installs an OS-appropriate nftables service;
- permits VPN-only SSH administration;
- opens only the service ports required by each inventory group;
- restricts PostgreSQL, Patroni, Garage, monitoring, HAProxy and web ports to
  their approved source groups.

### 04 — RAID and Garage S3 storage

- **File:** [`04_S3_STORAGE_service.yml`](../ansible/04_S3_STORAGE_service.yml)
- **Target:** `s3_servers`

Actions:

- installs `mdadm` and filesystem utilities on the storage nodes;
- runs the idempotent storage configuration script one host at a time;
- creates or safely assembles `/dev/md0` as the Garage RAID1 array;
- creates or safely assembles `/dev/md1` as the backup RAID1 array;
- formats new arrays as ext4, mounts them at `/srv/storage` and `/srv/backup`,
  and writes UUID-based `/etc/fstab` entries;
- updates `mdadm.conf` and the initramfs;
- refuses to overwrite disks containing unexpected signatures or an unexpected
  RAID layout;
- validates the three-node Garage inventory and required Vault credentials;
- installs the pinned Garage binary and a dedicated locked service account;
- deploys Garage configuration and its systemd service;
- connects the east, west and cloud Garage nodes through the coordinator;
- creates and applies the initial three-zone cluster layout;
- refuses to overwrite pending or unexpected existing layout changes;
- waits until all three storage nodes are connected and healthy;
- creates the `product-images` bucket with a 2 GiB quota;
- creates the `monitoring-logs` bucket with an 8 GiB quota;
- imports separate application and Loki access keys and assigns only the
  required bucket permissions;
- verifies that anonymous access and cross-bucket access are denied;
- performs upload, download and deletion tests in both buckets.

### 05 — PostgreSQL high-availability cluster

- **File:** [`05_DB_cluster.yml`](../ansible/05_DB_cluster.yml)
- **Targets:** `etcd_servers` and `patroni_servers`

Actions:

- checks for an existing Patroni configuration and refuses an unsafe in-place
  migration from etcd v2;
- validates that etcd runs on Ubuntu and uses a supported one- or three-member
  topology;
- installs `etcd-server` and `etcd-client`;
- creates the etcd v3 data directory, environment configuration and explicit
  systemd service;
- starts all etcd members and waits for a healthy endpoint;
- verifies that all required PostgreSQL, replication, application, backup and
  Patroni API credentials exist in Vault;
- installs PostgreSQL 18, Patroni and required Python database libraries;
- stops and masks the distribution-managed default PostgreSQL cluster;
- creates the Patroni configuration and PostgreSQL data directories;
- installs the Patroni configuration and explicit systemd unit;
- configures one PostgreSQL primary and one streaming replica through Patroni;
- waits until every database node is healthy and running as either Primary or
  a streaming replica;
- identifies the current Primary through the Patroni REST API;
- requires exactly one Primary before changing database objects;
- copies `shopdb.sql` from the repository and applies it only on the Primary;
- creates or updates the application user and the read-only `backup_reader`
  role;
- prints the final Patroni cluster state.

The current inventory uses a three-member etcd quorum on `east_db`, `west_db`
and `cloud_quorum`, while PostgreSQL/Patroni runs on `east_db` and `west_db`.

### 06 — Web application, HAProxy and external DNS

- **File:** [`06_WEB_HAPROXY_DNS_service.yml`](../ansible/06_WEB_HAPROXY_DNS_service.yml)
- **Targets:** `web_servers`, `balance_servers` and `inet_dns_servers`

Actions on web nodes:

- installs Docker and Docker Compose on both Alpine web servers;
- copies the NGINX and Python backend project from `ansible/files/shop-web`;
- creates the protected application environment file from Vault variables;
- validates the Docker Compose configuration;
- builds and starts the containers;
- waits for NGINX and verifies the application health endpoint.

Actions on load balancers:

- installs HAProxy on the east and west load-balancer nodes;
- generates and validates the HAProxy configuration;
- gives priority to the local web node and keeps the remote web node as a
  backup;
- exposes the PostgreSQL frontend and routes it only to the current Patroni
  Primary;
- exposes the Garage S3 frontend and health-checks all Garage nodes;
- optionally enables HTTPS when the TLS certificate exists;
- enables the authenticated HAProxy statistics page;
- verifies the web frontend and statistics endpoint.

Actions on the external DNS node:

- installs dnsmasq and the HAProxy health-check service;
- publishes `shop.project.local` records only for healthy HAProxy nodes;
- periodically checks both site load balancers;
- automatically removes an unhealthy address and restores it after recovery;
- reloads dnsmasq only when the active record set changes;
- verifies DNS resolution through the local external DNS service.

### 07 — Internal CA and TLS certificates

- **File:** [`07_TLS_certificates.yml`](../ansible/07_TLS_certificates.yml)
- **Targets:** local automation-node and `balance_servers`

Actions:

- creates `/home/ansible_admin/project-certs` on automation-node with restricted
  permissions;
- generates a 4096-bit internal root CA key and a ten-year CA certificate;
- generates a 2048-bit HAProxy private key and certificate-signing request;
- creates the required DNS and IP Subject Alternative Names;
- replaces an outdated HAProxy certificate when required addresses are absent;
- signs the HAProxy certificate for 825 days;
- builds the combined PEM file required by HAProxy;
- copies the PEM file to both load balancers with mode `0600`;
- runs the HAProxy role with TLS explicitly enabled;
- validates and restarts HAProxy with the HTTPS configuration.

The CA private key remains on automation-node and must be protected and backed
up securely.

### 08 — Install the internal CA for browsers

- **File:** [`08_install_ca_firefox.yml`](../ansible/08_install_ca_firefox.yml)
- **Target:** `hypervisor_hosts`

Actions:

- installs the operating-system and Firefox certificate tools;
- copies the project root CA into the system trust directory;
- updates the Debian/Ubuntu system CA store;
- removes the obsolete single-load-balancer `/etc/hosts` entry;
- adds both east and west load-balancer addresses for `shop.project.local`;
- locates existing Firefox profiles under `/home`;
- removes an older certificate with the same nickname from each profile;
- imports the current project CA into every detected Firefox NSS database.

If a Firefox profile does not yet exist, start Firefox once and rerun this
playbook.

### 09 — Central monitoring server

- **File:** [`09_MONITORING_server.yml`](../ansible/09_MONITORING_server.yml)
- **Target:** `monitoring_servers`

Actions:

- validates the monitoring server operating system;
- installs Prometheus 3.5.0 and creates its dedicated service account,
  directories, configuration and systemd service;
- installs Loki 3.5.1 with its own user, directories, configuration and
  systemd service;
- installs Grafana OSS from the official package repository;
- sets the Grafana administrator password from Vault;
- configures the project overview as the Grafana home dashboard;
- starts Prometheus, Loki and Grafana and checks their HTTP endpoints;
- provisions Prometheus and Loki data sources;
- deploys the project, host, container and log dashboards;
- removes obsolete or conflicting dashboard provisioning files;
- provisions alert rules and the notification policy;
- configures the Telegram contact point with Vault-protected credentials.

### 10 — Monitoring agents

- **File:** [`10_MONITORING_agents.yml`](../ansible/10_MONITORING_agents.yml)
- **Targets:** `alloy_agents` and `node_exporter_agents`

Actions:

- installs Grafana Alloy on supported Alpine and Ubuntu systems;
- configures the official Grafana package repository on Ubuntu;
- grants Alloy access to the required system logs and Docker data;
- enables Docker/container collection only for hosts in `docker_servers`;
- sends metrics to the central Prometheus remote-write endpoint;
- sends logs to the central Loki push endpoint;
- enables and starts the Alloy service;
- optionally installs and starts Node Exporter on selected Alpine or Ubuntu
  hosts.

In the current inventory, `alloy_agents` covers the infrastructure,
hypervisors and external DNS node. The `node_exporter_agents` child groups are
currently commented out, so the Node Exporter play has no targets until hosts
are added to that group.

### 11 — Restic backup service

- **File:** [`11_BACKUP_service.yml`](../ansible/11_BACKUP_service.yml)
- **Targets:** `east_storage` and `west_storage`
- **Execution mode:** one storage node at a time with `serial: 1`

Actions:

- validates both storage nodes, backup schedules and Vault credentials;
- installs Restic, rclone and the PostgreSQL client;
- requires the dedicated `/srv/backup` RAID1 mount;
- creates the locked `restic_sysuser` service account;
- creates protected configuration, staging, status and cache directories;
- creates separate local Restic repositories for application images, Loki
  logs and the PostgreSQL database;
- installs the Restic password, PostgreSQL `.pgpass` data and read-only rclone
  S3 credentials with mode `0600`;
- initializes absent repositories and verifies access to each repository;
- installs and syntax-checks the S3, database and maintenance Bash scripts;
- synchronizes the `product-images` and `monitoring-logs` buckets into staging
  directories before saving Restic snapshots;
- detects the current PostgreSQL Primary dynamically before running `pg_dump`;
- verifies that the same node is still Primary after the dump and retries if a
  failover occurred;
- validates the dump with `pg_restore --list` before saving it to Restic;
- applies separate retention policies and runs `restic check` during weekly
  maintenance;
- removes obsolete SSH/SFTP backup configuration and old timer units;
- installs and enables systemd services and timers;
- staggers east and west backup schedules to avoid both nodes running the same
  job simultaneously;
- can run the first S3 and database backup immediately when
  `backup_run_now=true` is supplied.

Run and start the first backups immediately:

```bash
ansible-playbook 11_BACKUP_service.yml --ask-vault-pass -e backup_run_now=true
```

---

## Operational database playbooks

The following playbooks are not part of the initial `00`–`11` deployment
sequence. They are used for planned PostgreSQL role changes.

### Switch Primary to east_db

**File:** [`db_switch_to_east.yml`](../ansible/db_switch_to_east.yml)

Actions:

- runs one forced Patroni switchover for the `project-postgres` cluster;
- selects `east_db` as the candidate Primary;
- displays the resulting Patroni cluster table.

```bash
ansible-playbook db_switch_to_east.yml --ask-vault-pass
```

### Switch Primary to west_db

**File:** [`db_switch_to_west.yml`](../ansible/db_switch_to_west.yml)

Actions:

- runs one forced Patroni switchover for the `project-postgres` cluster;
- selects `west_db` as the candidate Primary;
- displays the resulting Patroni cluster table.

```bash
ansible-playbook db_switch_to_west.yml --ask-vault-pass
```

---

## Useful verification commands

Check connectivity to every managed host:

```bash
ansible all -m ping --ask-vault-pass
```

Check one inventory group:

```bash
ansible web_servers -m ping --ask-vault-pass
```

Preview changes where the modules support check mode:

```bash
ansible-playbook 03_FIREWALL_DNS.yml --check --diff --ask-vault-pass
```

Show the affected hosts and tasks without making changes:

```bash
ansible-playbook 06_WEB_HAPROXY_DNS_service.yml --list-hosts --list-tasks --ask-vault-pass
```

Run with more detailed troubleshooting output:

```bash
ansible-playbook 05_DB_cluster.yml --ask-vault-pass -vv
```

Because playbooks are executed from automation-node, all local paths, SSH keys,
Vault files and generated certificates referenced by the playbooks must be
available on that node.
