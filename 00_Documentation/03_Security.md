# Infrastructure Security

## Overview

This document describes the security model used in the distributed
infrastructure project. The environment is a test lab distributed across two
physical hypervisors, three routed LAN segments and a Tailscale overlay network.
Terraform creates the networks and virtual machines, while Ansible applies the
accounts, SSH policy, firewall rules, service credentials, internal PKI and
backup permissions.

The design follows several basic principles:

- administrative access is separated from application traffic;
- remote administration uses SSH keys instead of passwords;
- direct root login is disabled on project virtual machines;
- every person and service uses a separate account;
- a local emergency account is available only through the VM console;
- routers and servers use default-deny nftables policies;
- management traffic reaches the lab through Tailscale;
- client web traffic is protected with TLS issued by an internal CA;
- secrets are passed from Ansible Vault and are not stored in plaintext in Git;
- application, monitoring and backup services receive separate credentials.

> [!IMPORTANT]
> This is a security design for a private educational lab. It demonstrates
> layered protection, but it is not presented as a complete production
> security baseline. The [Known limitations](#known-limitations-and-future-hardening)
> section records the remaining risks.

## Security architecture

The main protection layers are shown below.

| Layer | Main controls |
|---|---|
| Physical and virtualization | Two separate hypervisors, KVM/libvirt permissions, AppArmor access rules and isolated virtual networks |
| Network | Separate East, West and Cloud subnets, Tailscale overlay routing, nftables filtering and WAN-only NAT |
| Host access | SSH keys, non-standard SSH port, `AllowUsers`, disabled root and password login, separate administrators |
| Application access | Source-restricted service ports, PostgreSQL roles, Garage S3 keys and HAProxy authentication |
| Encryption | HTTPS at HAProxy, internal CA, encrypted Ansible Vault and encrypted Restic repositories |
| Operations | Central monitoring and logs, automated backups, reproducible Terraform and Ansible configuration |

The project networks are separated as follows:

| Zone | Subnet | Security purpose |
|---|---:|---|
| East branch | `192.168.72.0/27` | Isolated branch services behind `east_router` |
| West branch | `192.168.73.0/27` | Isolated branch services behind `west_router` |
| Cloud segment | `192.168.74.0/27` | Monitoring, quorum and the third Garage node |
| Tailscale | `100.64.0.0/10` | Administrative overlay and routed access between sites |

The service VMs use private project addresses. The Alpine routers connect each
LAN to Tailscale and provide controlled outbound NAT through their WAN
interfaces. NAT is not applied to the VPN interface.

## Identity and account separation

The project does not use one shared account for every task.

| Account | Purpose | Remote access | Privileges |
|---|---|---|---|
| `ansible_admin` | Ansible automation | SSH key from `automation-node` | Passwordless `sudo` for unattended automation |
| `admin_aleksei` | Human administrator for Host 1 | Personal Ed25519 key | `sudo`/`wheel`; local password is used only for `sudo` |
| `admin_ilja` | Human administrator for Host 2 | Personal Ed25519 key | `sudo`/`wheel`; local password is used only for `sudo` |
| `system_admin` | Emergency local administrator | No SSH key and excluded from `AllowUsers` | Console-only `sudo`/`wheel` access |
| `garage` | Garage service | No interactive login | Access only to Garage configuration and data |
| `restic_sysuser` | Backup service | Locked password and `/usr/sbin/nologin` | Access only to protected backup paths and repositories |
| PostgreSQL roles | Database administration, replication, application and backup | Database protocol only | Role-specific database permissions |

The human administrator public keys are generated on the corresponding
hypervisors and distributed to the infrastructure VMs by
[`02_VM_initial_boorstrap.yml`](../ansible/02_VM_initial_boorstrap.yml). The
private key used by `ansible_admin` is stored only on `automation-node` at
`~/.ssh/ansible`; it is not part of the repository.

The console-only `system_admin` account provides recovery access when the VPN,
network or SSH configuration is unavailable. Ansible removes any
`authorized_keys` file from this account and deliberately omits it from the SSH
allowlist.

Service accounts follow the least-privilege principle. They use locked
passwords or non-login shells where possible and own only the files needed by
their service.

## SSH security

SSH configuration is applied during cloud-init and reinforced by Ansible.

The effective policy for project virtual machines is:

- `PermitRootLogin no`;
- `PasswordAuthentication no`;
- `KbdInteractiveAuthentication no`;
- `PermitEmptyPasswords no`;
- `PubkeyAuthentication yes`;
- `AuthenticationMethods publickey` after the initial bootstrap;
- only `ansible_admin`, `admin_aleksei` and `admin_ilja` are in `AllowUsers`;
- infrastructure SSH uses port `2222` by default;
- firewalls accept the SSH port only from Tailscale addresses.

Ubuntu cloud-init locks the `ansible_admin` password. Alpine requires an
unlocked shadow entry before it will accept public-key login without PAM, so
the Alpine templates contain the hash of a discarded high-entropy value.
Password and keyboard-interactive authentication remain disabled, so this hash
cannot be used for remote login.

The automation account has passwordless `sudo` because Ansible must perform
unattended configuration. This makes the automation-node and its private key
high-value assets. Access to that node must therefore remain restricted to the
administrators and the Tailscale management path.

Relevant implementation files:

- [`terraform/cloud-init/router-alpine-user-data.yaml.tftpl`](../terraform/cloud-init/router-alpine-user-data.yaml.tftpl)
- [`terraform/cloud-init/server-alpine-user-data.yaml.tftpl`](../terraform/cloud-init/server-alpine-user-data.yaml.tftpl)
- [`terraform/cloud-init/server-ubuntu-user-data.yaml.tftpl`](../terraform/cloud-init/server-ubuntu-user-data.yaml.tftpl)
- [`ansible/roles/automation_sshd`](../ansible/roles/automation_sshd)
- [`ansible/02_VM_initial_boorstrap.yml`](../ansible/02_VM_initial_boorstrap.yml)

## VPN and management-plane protection

Tailscale provides the encrypted overlay that connects the two physical hosts,
the virtual routers, the automation-node and administrator workstations. Each
router advertises its local `/27` subnet so that approved tailnet members can
reach private service addresses without exposing those services directly to
the Internet.

The router bootstrap performs the following security actions:

- reads the Tailscale auth key from a root-owned `0600` temporary file;
- joins the tailnet and advertises only the configured branch route;
- disables Tailscale SSH because the project uses hardened OpenSSH;
- removes the auth-key file immediately after successful registration;
- accepts router SSH only through `tailscale0`;
- permits UDP `41641` on the WAN interface for Tailscale connectivity.

Subnet routes must be approved in the Tailscale administration console. Access
to the tailnet control plane and reusable auth keys must be limited to project
administrators.

## Firewall and network access control

The project uses nftables directly rather than relying on UFW. The rules are
deployed by [`03_FIREWALL_DNS.yml`](../ansible/03_FIREWALL_DNS.yml).

### Router firewall

Every project router uses default-deny `input` and `forward` chains. The rules:

- drop invalid packets and accept established or related traffic;
- allow the loopback interface and ICMP;
- allow SSH only from `tailscale0`;
- allow DNS only from the router's own branch LAN;
- allow LAN-to-WAN and LAN-to-Tailscale forwarding;
- allow Tailscale-to-LAN forwarding for the advertised subnet;
- apply masquerading only when traffic exits through the WAN interface;
- restrict Node Exporter to the monitoring server and the VPN.

See
[`ansible/roles/router_firewall/templates/nftables.nft.j2`](../ansible/roles/router_firewall/templates/nftables.nft.j2).

### Server firewall

Guest servers also use a default-deny input policy. Ports are opened according
to the server's inventory group and the expected source hosts.

| Service | Port | Permitted sources |
|---|---:|---|
| SSH | `2222` | Tailscale addresses only |
| HAProxy web frontends | `80`, `443` | Project LANs and Tailscale |
| NGINX backend | `80` | HAProxy nodes only |
| HAProxy statistics | `8404` | Monitoring server and Tailscale |
| PostgreSQL | `5432` | Patroni peers, load balancers and backup nodes |
| Patroni REST API | `8008` | Patroni peers, load balancers and monitoring |
| etcd client/peer | `2379`, `2380` | etcd and Patroni cluster members |
| Garage S3 API | `3900` | Load balancers and explicitly approved clients |
| Garage RPC | `3901` | Garage cluster members only |
| Garage administration/metrics | `3903` | Garage, load-balancer and monitoring nodes |
| Grafana, Loki, Prometheus | `3000`, `3100`, `9090` | Project LANs and Tailscale |

See
[`ansible/roles/host_firewall/templates/project-host.nft.j2`](../ansible/roles/host_firewall/templates/project-host.nft.j2).

## TLS and internal PKI

The project uses a private certificate authority generated on
`automation-node`. The CA signs a certificate for the two HAProxy load
balancers and the `shop.project.local` service.

The current certificate configuration includes:

- a 4096-bit RSA internal CA key;
- a self-signed CA certificate with a ten-year lab lifetime;
- a 2048-bit RSA HAProxy server key;
- an 825-day server certificate;
- SAN entries for `shop.project.local`, the load-balancer names and both
  load-balancer IP addresses;
- a private certificate directory with mode `0700`;
- private key and combined PEM files with mode `0600`;
- a root-owned HAProxy certificate directory with mode `0700`;
- automatic HTTP-to-HTTPS redirection when TLS is enabled.

TLS terminates at HAProxy. NGINX runs as an internal backend and receives
traffic only from the two load balancers. The certificate is therefore not
installed directly on NGINX in the current architecture.

The public CA certificate is installed into the hypervisor system trust store
and existing Firefox profiles by
[`08_install_ca_firefox.yml`](../ansible/08_install_ca_firefox.yml). The CA
private key stays on `automation-node` and must never be copied to client
machines or committed to Git.

Implementation:

- [`07_TLS_certificates.yml`](../ansible/07_TLS_certificates.yml)
- [`ansible/roles/haproxy/templates/haproxy.cfg.j2`](../ansible/roles/haproxy/templates/haproxy.cfg.j2)

## Secrets management

Project secrets are referenced through
`ansible/group_vars/group/all/vault.yml`. The file in the repository is
encrypted with Ansible Vault using AES-256. It is intentionally safe for the
public project repository because it is encrypted and does **not** contain the
current operational keys or passwords.

The Vault password is not stored in the repository. Playbooks are normally
started with:

```bash
ansible-playbook <playbook>.yml --ask-vault-pass
```

Vault variables cover items such as:

- administrator password hashes and SSH ports;
- PostgreSQL, replication, backup and Patroni API passwords;
- Garage RPC, administration and metrics tokens;
- separate Garage keys for the application, Loki and backups;
- Grafana and HAProxy statistics credentials;
- Restic repository password and alerting tokens.

Tasks that handle plaintext credentials use `no_log: true` and, where
appropriate, `diff: false`. Runtime secret files such as `.env`, `.pgpass`,
`rclone.conf` and the Restic password file are deployed with mode `0600`.

Terraform secrets are supplied through an ignored `secrets.auto.tfvars` file or
environment variables. Terraform state and plan files are also excluded by
`.gitignore`, because state can contain sensitive values even when a variable
is marked `sensitive`.

Before every push, the following must be checked:

```bash
git status --short
git diff --cached
git grep -nEi '(password|secret|token|private[_ -]?key|auth[_ -]?key)' -- ':!documentation/'
```

The last command is a review aid, not proof that the repository is free of
secrets. Matches must be inspected manually because variable names and example
placeholders are expected.

## Service-level security

### PostgreSQL, Patroni and etcd

- PostgreSQL uses separate superuser, replication, application and backup
  accounts.
- Host-based authentication is generated from the inventory and permits only
  expected `/32` addresses.
- Network password authentication uses `scram-sha-256`.
- `backup_reader` is a non-superuser without database-creation, role-creation
  or replication privileges.
- Patroni's REST API uses separate Vault-managed basic-auth credentials.
- nftables restricts PostgreSQL, Patroni and etcd ports to cluster members and
  approved clients.

### Garage S3

- Garage cluster RPC uses a shared Vault-managed secret.
- Administration and metrics endpoints use separate tokens.
- Metrics require authentication.
- The web application, Loki and the backup service use separate S3 keys.
- Each key receives only the bucket permissions required by its service.
- Anonymous bucket access and cross-bucket access are explicitly tested and
  must remain denied.
- Garage runs as the dedicated non-login `garage` user.

### Web and load balancing

- HTTPS is terminated at HAProxy and HTTP requests are redirected to HTTPS.
- Only HAProxy nodes can reach the NGINX backend port.
- HAProxy statistics require Vault-managed HTTP basic authentication.
- Application database and S3 credentials are injected through a root-owned
  `.env` file instead of being embedded in the Docker Compose file.
- Uploaded filenames are sanitized and the demo backend restricts accepted
  image extensions.

### Monitoring and backups

- Grafana administrator and Telegram alerting credentials come from Vault.
- Monitoring ports are limited to the project LANs and Tailscale.
- Monitoring uses S3 Cluster for storage, which reduces failure and prevents loss of data.
- Backup jobs run as the locked `restic_sysuser` service account.
- The Garage backup key is read-only.
- Restic encrypts every repository and reads its password from a `0600` file.
- Database backups use a dedicated restricted PostgreSQL account and are
  created only from the current Patroni Primary.
- Backup repositories and staging directories use restrictive ownership and
  modes on the dedicated RAID1 backup volumes.

## Security incidents and remediation

Two security incidents occurred during development. Both were handled by
assuming that the exposed material could no longer be trusted and rotating it.

### Incident 1: certificate material committed to the repository

A certificate file was accidentally added to the Git repository. In this lab,
the impact was limited because the project owns its internal CA and can issue a
replacement certificate immediately.

Response:

1. the exposed certificate was treated as compromised;
2. new certificate material was generated and deployed;
3. certificate and private-key paths were kept outside the repository;
4. permissions were restricted to `0700` for directories and `0600` for
   private key/PEM files;
5. repository changes are now reviewed before every push.

A public certificate does not normally contain a secret, but a private key or
a PEM bundle containing the key is sensitive. If a private key is ever
committed, deleting the file in a later commit is insufficient: the key must be
rotated and the old material removed from Git history where appropriate.

### Incident 2: hardcoded password

An active password was temporarily hardcoded during development. The affected
passwords were changed after the issue was discovered.

Response:

1. the exposed credentials were rotated;
2. operational credentials were moved to Ansible Vault;
3. services now receive passwords through protected templates and environment
   files;
4. Ansible tasks that process secrets suppress logs and diffs;
5. Git review now includes searches for passwords, tokens and private keys.

The demo Python backend still contains a non-operational fallback string for
`DB_PASS`. The deployed `.env` file overrides it with the Vault value, so it is
not the active password. Nevertheless, the fallback should be removed so that
the application fails closed when `DB_PASS` is missing.

## Known limitations and future hardening

The following limitations are accepted for the current educational lab and
must be addressed before using the design for production data:

- `host_key_checking = False` is enabled in `ansible.cfg` because Terraform
  frequently recreates VMs. This weakens SSH server identity verification.
  Production automation should manage known host keys and enable strict
  checking.
- TLS currently protects the client-to-HAProxy connection. HAProxy-to-NGINX,
  PostgreSQL, etcd and Garage internal traffic is protected by network
  isolation and firewall rules but is not encrypted end to end. Production
  deployments should add service TLS or mTLS.
- The local CA uses long lab certificate lifetimes and has no automated
  rotation, revocation list or OCSP service.
- Tailscale ACL policy is managed outside this repository. Tailnet ACLs, route
  approvals and reusable auth keys must be reviewed separately.
- Ansible Vault protects secrets at rest in Git, but decrypted values still
  exist temporarily in memory and in protected runtime files on managed hosts.
- The encrypted Vault file committed to this public repository contains
  non-current placeholder values. Real operational secrets must be supplied
  privately and must never be substituted into the committed copy.
- The backend fallback password should be removed and replaced by a mandatory
  environment-variable check.
- The nftables roles protect project routers and VMs. Security rules already
  present on the physical hypervisors remain a separate host-level
  responsibility.

## Related project files

- [`02_VM_initial_boorstrap.yml`](../ansible/02_VM_initial_boorstrap.yml) — users and SSH access
- [`03_FIREWALL_DNS.yml`](../ansible/03_FIREWALL_DNS.yml) — router and host firewalls
- [`07_TLS_certificates.yml`](../ansible/07_TLS_certificates.yml) — internal CA and HAProxy certificate
- [`08_install_ca_firefox.yml`](../ansible/08_install_ca_firefox.yml) — client trust configuration
- [`11_BACKUP_service.yml`](../ansible/11_BACKUP_service.yml) — protected backup service
- [`ansible/group_vars/all/project.yml`](../ansible/group_vars/all/project.yml) — non-secret security and network settings
- [`ansible/group_vars/group/all/vault.yml`](../ansible/group_vars/group/all/vault.yml) — encrypted example Vault
- [`terraform/cloud-init`](../terraform/cloud-init) — initial account and SSH hardening

