# Terraform Infrastructure Provisioning

## Overview

Terraform is responsible for provisioning the virtual infrastructure of this project on two remote KVM/QEMU hypervisors. It creates the isolated libvirt networks, virtual routers, application servers, storage volumes, cloud-init media, and VM domains required by the environment.

Terraform is executed on the `automation-node`. The libvirt provider connects from that node to both hypervisors over SSH and manages their local libvirt instances remotely.

Terraform provides the infrastructure layer only. After the virtual machines are available, Ansible performs the higher-level operating system and service configuration, including DNS, security hardening, PostgreSQL, Garage S3, web services, monitoring, and backups.

> Terraform creates and recreates infrastructure. Ansible configures the services running inside that infrastructure.


---

## Responsibilities

Terraform manages the following resources:

- Three isolated libvirt networks: `east-lan`, `west-lan`, and `cloud-lan`.
- Three Alpine Linux virtual routers.
- Application, database, storage, load-balancer, monitoring, and quorum VMs.
- The standalone external DNS VM connected to the libvirt `default` network.
- One directory-based libvirt storage pool per VM.
- Copy-on-write QCOW2 system disks based on immutable cloud images.
- Additional QCOW2 data and backup disks for the storage nodes.
- Per-VM cloud-init ISO images.
- CPU, memory, disk, network interface, autostart, and serial console settings.
- Initial users, SSH access, static addressing, swap, routing, NAT, firewalling, and Tailscale bootstrap through cloud-init.

Terraform does **not** configure application services such as PostgreSQL, Garage, NGINX, HAProxy, Prometheus, Grafana, Loki, or Restic. Those tasks belong to Ansible.

---

## Architecture

The Terraform provider connects to the hypervisors through their Tailscale addresses:

| Terraform provider | Hypervisor | Libvirt URI | Managed networks |
|---|---|---|---|
| `libvirt.host_1` | Host 1 | `qemu+ssh://ansible_admin@100.64.0.10/system` | `east-lan`, `cloud-lan`, and the existing `default` network |
| `libvirt.host_2` | Host 2 | `qemu+ssh://ansible_admin@100.64.0.11/system` | `west-lan` and the existing `default` network |

```mermaid
flowchart TD
    A[automation-node] -->|Terraform over SSH| H1[Host 1: KVM and libvirt]
    A -->|Terraform over SSH| H2[Host 2: KVM and libvirt]

    H1 --> E[EAST LAN: 192.168.72.0/27]
    H1 --> C[CLOUD LAN: 192.168.74.0/27]
    H2 --> W[WEST LAN: 192.168.73.0/27]

    E --> ER[east-router]
    C --> CR[cloud-router]
    W --> WR[west-router]

    ER <-->|Tailscale| CR
    CR <-->|Tailscale| WR
```

The `default` libvirt network provides WAN connectivity and DHCP to the router WAN interfaces. The project LANs are isolated networks without libvirt DHCP. Their servers use static addresses and reach other networks through the site routers.

---

## Provisioning Order

Terraform dependencies enforce the following creation sequence:

1. Create the required isolated libvirt networks.
2. Create the cloud, east, and west router VMs.
3. Bootstrap the routers with cloud-init.
4. Start Tailscale, advertise the site subnets, and enable routing and NAT.
5. Wait 90 seconds for router initialization.
6. Create the server VMs on both hypervisors.
7. Create the standalone external DNS VM on the `default` network.

The server modules depend on `time_sleep.wait_after_routers`. This prevents LAN-only servers from starting before their gateways have had time to initialize.

---

## Terraform Directory Structure

```text
terraform/
├── .terraform.lock.hcl
├── providers.tf
├── variables.tf
├── terraform.tfvars
├── locals.tf
├── networks.tf
├── routers.tf
├── machines.tf
├── external.tf
├── wait_for_router_init.tf
├── cloud-init/
│   ├── meta-data.yaml.tftpl
│   ├── router-alpine-user-data.yaml.tftpl
│   ├── router-network-config.yaml.tftpl
│   ├── server-alpine-user-data.yaml.tftpl
│   ├── server-ubuntu-user-data.yaml.tftpl
│   ├── server-network-config.yaml.tftpl
│   ├── external-alpine-user-data.yaml.tftpl
│   └── external-network-config.yaml.tftpl
└── modules/
    └── vm/
        ├── versions.tf
        ├── variables.tf
        ├── storage.tf
        ├── cloud-init.tf
        └── domain.tf
```

| File | Purpose |
|---|---|
| `.terraform.lock.hcl` | Records the provider versions and checksums selected by Terraform. |
| `providers.tf` | Defines Terraform and provider versions and both remote libvirt connections. |
| `variables.tf` | Declares the router, server, image, SSH, secret, and host-selection variables. |
| `terraform.tfvars` | Contains the current VM inventory, resources, addresses, disks, and network assignments. |
| `locals.tf` | Loads the SSH public key, maps base images, and separates machines by hypervisor. |
| `networks.tf` | Creates the east, west, and cloud isolated libvirt networks. |
| `routers.tf` | Instantiates the shared VM module for the router VMs. |
| `machines.tf` | Instantiates the shared VM module for the internal server VMs. |
| `external.tf` | Defines and creates standalone VMs connected directly to the `default` network. |
| `wait_for_router_init.tf` | Adds the 90-second dependency delay between routers and internal servers. |
| `cloud-init/` | Contains OS bootstrap and network configuration templates. |
| `modules/vm/` | Reusable implementation of storage pools, disks, cloud-init media, interfaces, and VM domains. |

---

## Requirements

### Automation node

The `automation-node` requires:

- Terraform `1.6` or newer.
- Ansible for the automated Terraform wrapper playbook.
- The project repository.
- SSH access as `ansible_admin` to both hypervisors.
- The private key corresponding to `~/.ssh/ansible.pub`.
- Network access to `100.64.0.10` and `100.64.0.11` through Tailscale.

### Hypervisors

Both hypervisors require:

- KVM/QEMU and libvirt.
- The `ansible_admin` account with permission to manage the system libvirt instance.
- A working libvirt `default` NAT network.
- The following base images at the configured paths:

```text
/var/lib/libvirt/images/templates/ubuntu-26.04-server-cloudimg-amd64.img
/var/lib/libvirt/images/templates/alpine-3.24.2-x86_64-cloudinit-r0.qcow2
```

- Read access to the template images for the QEMU service account.
- Write access to `/var/lib/libvirt/images/vms/` for Terraform-managed VM disks.

The Ansible hypervisor bootstrap playbook prepares the libvirt directories, file ownership, permissions, and AppArmor rules used by Terraform.

### Provider versions

The root configuration currently requires:

| Component | Version constraint |
|---|---|
| Terraform | `>= 1.6` |
| `dmacvicar/libvirt` | `= 0.9.9` |
| `hashicorp/time` | `~> 0.13` |

---

## Configuration

The main infrastructure inventory is stored in `terraform/terraform.tfvars`.

### Important global variables

| Variable | Current/default value | Description |
|---|---|---|
| `images_dir` | `/var/lib/libvirt/images` | Parent directory used for VM pools and disks. |
| `storage_pool` | `default` | Prefix used in the generated per-VM pool names. |
| `ubuntu_image` | `/var/lib/libvirt/images/templates/ubuntu-26.04-server-cloudimg-amd64.img` | Ubuntu base image. |
| `alpine_image` | `/var/lib/libvirt/images/templates/alpine-3.24.2-x86_64-cloudinit-r0.qcow2` | Alpine base image. |
| `ansible_admin_public_key_file` | `~/.ssh/ansible.pub` | Public key installed in every VM. |
| `ssh_port` | `2222` | SSH port configured by cloud-init. |
| `enabled_hosts` | `host_1`, `host_2` | Selects which hypervisors receive resources. |

### Host selection

`enabled_hosts` can be used to limit a test deployment to one hypervisor:

```bash
terraform plan -var='enabled_hosts=["host_1"]'
```

The local filters in `locals.tf` select only the routers and servers assigned to an enabled host. Network resources use the same variable through conditional `count` expressions.

> The production configuration enables both hosts. A single-host deployment is intended for testing and does not provide the full distributed architecture.

---

## Secrets

Tailscale authentication keys must not be placed in the tracked `terraform.tfvars` file. Create `terraform/secrets.auto.tfvars` locally:

```hcl
router_tailscale_auth_keys = {
  cloud_router = "tskey-auth-REPLACE_ME"
  east_router  = "tskey-auth-REPLACE_ME"
  west_router  = "tskey-auth-REPLACE_ME"
  inet_dns     = "tskey-auth-REPLACE_ME"
}
```

The three router entries are used by `routers.tf`. The `inet_dns` entry is used by the external VM module in `external.tf`.

The same variable can alternatively be provided through the environment:

```bash
export TF_VAR_router_tailscale_auth_keys='{"cloud_router":"tskey-auth-REPLACE_ME","east_router":"tskey-auth-REPLACE_ME","west_router":"tskey-auth-REPLACE_ME","inet_dns":"tskey-auth-REPLACE_ME"}'
```

Security requirements:

- Never commit `secrets.auto.tfvars` or a Terraform state file.
- Use short-lived, tagged, or reusable Tailscale keys according to the deployment procedure.
- Revoke an authentication key if it is exposed.
- Protect the local Terraform state because rendered cloud-init data can contain sensitive values.
- Cloud-init stores each Tailscale key temporarily in a root-only file and deletes it after `tailscale up` completes.

---

## Current Virtual Machine Inventory

The following tables reflect the current `terraform.tfvars` configuration.

### Routers

| VM | Hypervisor | OS | vCPU | RAM | System disk | WAN | LAN address | Advertised subnet |
|---|---|---:|---:|---:|---:|---|---|---|
| `east_router` | Host 1 | Alpine | 1 | 512 MiB | 5 GiB | `default` | `192.168.72.1` | `192.168.72.0/27` |
| `west_router` | Host 2 | Alpine | 1 | 512 MiB | 5 GiB | `default` | `192.168.73.1` | `192.168.73.0/27` |
| `cloud_router` | Host 1 | Alpine | 1 | 512 MiB | 5 GiB | `default` | `192.168.74.1` | `192.168.74.0/27` |

Each router has two VirtIO interfaces: a DHCP WAN interface on `default` and a static interface on its isolated LAN.

### Internal servers

| VM | Hypervisor | OS | vCPU | RAM | System disk | Address | Gateway | Purpose |
|---|---|---:|---:|---:|---:|---|---|---|
| `east-load-balancer` | Host 1 | Alpine | 1 | 1 GiB | 20 GiB | `192.168.72.2` | `192.168.72.1` | East HAProxy entry point |
| `east-web` | Host 1 | Alpine | 2 | 3 GiB | 20 GiB | `192.168.72.3` | `192.168.72.1` | East web application node |
| `east-db` | Host 1 | Ubuntu | 2 | 3 GiB | 20 GiB | `192.168.72.4` | `192.168.72.1` | East PostgreSQL/Patroni node |
| `east-storage` | Host 1 | Ubuntu | 1 | 3 GiB | 20 GiB | `192.168.72.5` | `192.168.72.1` | East Garage and backup node |
| `west-load-balancer` | Host 2 | Alpine | 1 | 1 GiB | 20 GiB | `192.168.73.2` | `192.168.73.1` | West HAProxy entry point |
| `west-web` | Host 2 | Alpine | 2 | 3 GiB | 20 GiB | `192.168.73.3` | `192.168.73.1` | West web application node |
| `west-db` | Host 2 | Ubuntu | 2 | 3 GiB | 20 GiB | `192.168.73.4` | `192.168.73.1` | West PostgreSQL/Patroni node |
| `west-storage` | Host 2 | Ubuntu | 1 | 3 GiB | 20 GiB | `192.168.73.5` | `192.168.73.1` | West Garage and backup node |
| `cloud-monitoring` | Host 1 | Ubuntu | 1 | 6 GiB | 30 GiB | `192.168.74.3` | `192.168.74.1` | Monitoring and logging stack |
| `cloud-quorum` | Host 1 | Ubuntu | 1 | 2 GiB | 20 GiB | `192.168.74.5` | `192.168.74.1` | etcd quorum node |
| `cloud-s3` | Host 1 | Ubuntu | 1 | 2 GiB | 20 GiB | `192.168.74.6` | `192.168.74.1` | Cloud Garage and backup node |

### Storage data disks

Each storage VM receives four additional 15 GiB disks:

| Guest disks | Stable serials | Intended use |
|---|---|---|
| `vdb`, `vdc` | `garage1`, `garage2` | Garage S3 RAID1 array |
| `vdd`, `vde` | `backup1`, `backup2` | Restic backup RAID1 array |

The disk serials allow Ansible and guest-side scripts to identify the correct devices without relying only on kernel device ordering.

### External VM

| VM | Hypervisor | OS | vCPU | RAM | System disk | Network | Addressing | Purpose |
|---|---|---:|---:|---:|---:|---|---|---|
| `inet-dns` | Host 1 | Alpine | 1 | 512 MiB | 5 GiB | `default` | DHCP + Tailscale | External DNS node accessible through the tailnet |

---

## Network Layout

| Segment | CIDR | Router | Libvirt network | Hypervisor | Workloads |
|---|---|---|---|---|---|
| EAST | `192.168.72.0/27` | `192.168.72.1` | `east-lan` | Host 1 | Load balancer, web, database, storage |
| WEST | `192.168.73.0/27` | `192.168.73.1` | `west-lan` | Host 2 | Load balancer, web, database, storage |
| CLOUD | `192.168.74.0/27` | `192.168.74.1` | `cloud-lan` | Host 1 | Monitoring, quorum, Garage S3 |

### Router traffic flow

The router cloud-init configuration performs the initial network bootstrap:

- Enables IPv4 forwarding.
- Starts Tailscale and advertises the local `/27` subnet.
- Accepts routes advertised by the other site routers.
- Permits forwarding between the LAN and `tailscale0`.
- Permits LAN traffic to the WAN interface.
- Applies source NAT only when LAN traffic exits through the WAN interface.
- Restricts router SSH access to the Tailscale interface.
- Allows established and related traffic and required DHCP, ICMP, and Tailscale traffic.

Static MAC addresses are used because the cloud-init network templates match each guest interface by MAC address. Routers therefore receive predictable `eth0` WAN and `eth1` LAN configurations, while servers receive their expected static LAN configuration.

---

## Reusable VM Module

All router, server, and external VM definitions use `terraform/modules/vm`.

### Storage pool

The module creates a separate directory-based storage pool for every VM:

```text
Pool name: default-<vm-name>
Pool path: /var/lib/libvirt/images/vms/<vm-name>
```

Separating the VMs into individual pools simplifies inspection, cleanup, and ownership of their disks.

### System disk

The system disk is a QCOW2 volume with an immutable cloud image as its backing store. This reduces duplicated storage and allows a VM to be recreated from a known base image.

```text
Guest device: vda
Bus: virtio
Format: qcow2
```

### Additional disks

Optional additional QCOW2 disks are created from the `extra_drives` list. The module maps them sequentially from `vdb` through `vdi` and assigns the configured guest-visible serial number.

### Cloud-init disk

The module renders three cloud-init data sources:

- `user-data` for the operating system bootstrap.
- `meta-data` for the instance ID and hostname.
- `network-config` for DHCP or static addressing.

They are combined into a per-VM ISO and attached as a SATA CD-ROM.

### Domain configuration

Each domain uses:

- KVM virtualization.
- The `x86_64` architecture.
- VirtIO disks and network adapters.
- Autostart by default.
- Immediate start after creation.
- A serial PTY console by default.

The current module does not define a graphical display or virtual video adapter because administration is performed through SSH and the serial console.

---

## Cloud-init Bootstrap

### Common server bootstrap

Ubuntu and Alpine server templates:

- Set the hostname.
- Create the `ansible_admin` account.
- Install the automation-node SSH public key.
- Grant passwordless sudo access to the automation account.
- Disable root SSH access and password authentication.
- Configure SSH on port `2222`.
- Install Python so that Ansible can manage the node.
- Grow the root partition and filesystem.
- Create and enable a swap file.
- Apply the static address, gateway, and DNS settings.

### Router bootstrap

The Alpine router template additionally:

- Installs nftables and Tailscale.
- Enables IPv4 forwarding.
- Configures the initial firewall and WAN masquerading.
- Starts Tailscale with the supplied authentication key.
- Advertises the router's LAN subnet.
- Accepts the other project routes.
- Removes the temporary authentication-key file.
- Makes SSH available after the VPN and firewall are initialized.

### External DNS bootstrap

The external Alpine template:

- Receives its libvirt-network address through DHCP.
- Connects to Tailscale.
- Accepts project subnet routes.
- Binds SSH to the node's Tailscale IPv4 address.

Cloud-init performs only the initial bootstrap. Long-term configuration and service management are handled by Ansible.

---

## Deployment

All commands are run on the `automation-node` from the cloned repository.

### 1. Check hypervisor connectivity

```bash
ssh ansible_admin@100.64.0.10 'virsh -c qemu:///system list --all'
ssh ansible_admin@100.64.0.11 'virsh -c qemu:///system list --all'
```

### 2. Create the secret variables file

Create `terraform/secrets.auto.tfvars` as described in the [Secrets](#secrets) section.

### 3. Initialize Terraform

Initialization downloads the required providers and creates the dependency lock file:

```bash
terraform -chdir=terraform init
```

Run `terraform init -upgrade` only when intentionally updating permitted provider versions.

### 4. Format and validate the configuration

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
```

### 5. Review the execution plan

```bash
terraform -chdir=terraform plan -out=terraform.tfplan
```

Read the plan carefully before applying it. In particular, check for unexpected VM or volume replacement operations.

### 6. Apply the reviewed plan

```bash
terraform -chdir=terraform apply terraform.tfplan
```

### Automated deployment through Ansible

The repository also provides `ansible/01_TERRAFORM.yml`:

```bash
ansible-playbook -i ansible/inventory ansible/01_TERRAFORM.yml
```

This playbook runs locally on the `automation-node` and:

1. Creates a non-interactive Terraform plan.
2. Uses the detailed exit code to detect whether changes exist.
3. Applies the saved plan only when Terraform reports changes.
4. Reports when the infrastructure is already current.
5. Removes the temporary `ansible.tfplan` file in all cases.

> Run `terraform init` at least once before using the Ansible wrapper because the playbook performs `plan` and `apply`, but not provider initialization.

---

## Applying Configuration Changes

Use the normal plan-and-apply workflow whenever VM resources, addresses, disks, or networks change:

```bash
terraform -chdir=terraform fmt -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=terraform.tfplan
terraform -chdir=terraform apply terraform.tfplan
```

Important behavior:

- CPU, memory, disk, and domain changes may update a VM or require its replacement depending on the provider resource.
- Changing a base image or system disk definition can recreate the VM disk and erase guest-side changes.
- Increasing an extra disk in Terraform does not automatically grow the guest partition, RAID array, filesystem, or mount.
- A modified cloud-init ISO does not guarantee that cloud-init will rerun inside an existing VM.
- Routine operating system and service changes should be made through Ansible instead of forcing VM replacement.
- Always review replacement markers in `terraform plan` before applying.

---

## Verification

### Terraform state

```bash
terraform -chdir=terraform state list
terraform -chdir=terraform show
```

### Hypervisor resources

Host 1:

```bash
ssh ansible_admin@100.64.0.10 'virsh -c qemu:///system net-list --all && virsh -c qemu:///system list --all && virsh -c qemu:///system pool-list --all'
```

Host 2:

```bash
ssh ansible_admin@100.64.0.11 'virsh -c qemu:///system net-list --all && virsh -c qemu:///system list --all && virsh -c qemu:///system pool-list --all'
```

### Router and server access

```bash
ssh -p 2222 ansible_admin@192.168.72.1
ssh -p 2222 ansible_admin@192.168.73.1
ssh -p 2222 ansible_admin@192.168.74.1
```

Example internal-server checks:

```bash
ssh -p 2222 ansible_admin@192.168.72.3 'hostname && ip address && ip route'
ssh -p 2222 ansible_admin@192.168.73.4 'hostname && ip address && ip route'
ssh -p 2222 ansible_admin@192.168.74.3 'hostname && ip address && ip route'
```

### Serial console

If SSH is not yet available, connect from the corresponding hypervisor:

```bash
sudo virsh console east_router
```

Press `Ctrl+]` to leave the virsh console.

---

## Destroying the Infrastructure

Destroying Terraform resources removes VM domains, their Terraform-managed volumes and pools, and the managed isolated networks. Data stored only inside those volumes will be lost.

Create and inspect a destruction plan first:

```bash
terraform -chdir=terraform plan -destroy -out=destroy.tfplan
terraform -chdir=terraform show destroy.tfplan
```

Apply it only after confirming backups and the full resource list:

```bash
terraform -chdir=terraform apply destroy.tfplan
```

Before destruction:

- Confirm that Garage, PostgreSQL, and Restic data has been backed up where required.
- Confirm that the correct Terraform state and workspace are active.
- Check that no manually created files are stored inside the Terraform-managed VM pool directories.
- Do not delete state files before Terraform has removed the resources.

---

## Terraform State

The current project uses local Terraform state. Terraform state maps the HCL configuration to the actual libvirt networks, pools, volumes, and domains on both hypervisors.

State files can contain sensitive rendered values and must be protected:

- Do not commit `terraform.tfstate`, state backups, plan files, or secret variable files.
- Keep a secure backup of the current state.
- Do not run concurrent Terraform operations against the same state.
- Do not manually edit the state file.
- Use `terraform state` commands only after inspecting the target resource address.

If the project later requires concurrent administration, migrate the state to a remote backend with locking and encryption.

---

## Troubleshooting

### Terraform cannot connect to libvirt

Check SSH and libvirt access from the automation node:

```bash
ssh ansible_admin@100.64.0.10 'virsh -c qemu:///system uri'
ssh ansible_admin@100.64.0.11 'virsh -c qemu:///system uri'
```

Verify:

- Tailscale connectivity to both hypervisors.
- SSH key authentication for `ansible_admin`.
- The remote user's libvirt permissions.
- The `qemu+ssh` URIs in `providers.tf`.
- That the system libvirt daemon is running.

### Base image cannot be opened

Confirm that the configured file exists and is readable by the QEMU service account:

```bash
ssh ansible_admin@100.64.0.10 'ls -l /var/lib/libvirt/images/templates/'
ssh ansible_admin@100.64.0.11 'ls -l /var/lib/libvirt/images/templates/'
```

Also check the AppArmor rules created by the hypervisor bootstrap playbook.

### Storage pool already exists

An interrupted deployment or earlier manually created resource may conflict with the expected pool name. Inspect the pool and Terraform state before changing anything:

```bash
ssh ansible_admin@100.64.0.10 'virsh -c qemu:///system pool-list --all'
terraform -chdir=terraform state list
```

Do not remove a pool or its directory until its owner and data have been confirmed.

### Pool directory is not empty during deletion

Check for a remaining cloud-init ISO, VM disk, or manually created file in the VM directory. Compare the directory with the volumes known to libvirt and Terraform. Back up any unknown data before cleanup.

### VM starts but has no network

Check that:

- The VM NIC MAC matches the MAC in `terraform.tfvars`.
- The matching MAC is rendered into the cloud-init network configuration.
- The expected libvirt network is active.
- The router VM is running and its LAN address is configured.
- The 90-second router initialization completed successfully.

### Server cannot reach another site

On the site router, verify Tailscale and advertised routes:

```bash
sudo tailscale status
ip route
sudo nft list ruleset
```

Also confirm that the subnet routes have been approved in the Tailscale administration policy.

### Cloud-init did not complete

Ubuntu:

```bash
sudo cloud-init status --long
sudo journalctl -u cloud-init -u cloud-final --no-pager
```

Alpine:

```bash
sudo tail -n 200 /var/log/cloud-init.log
sudo tail -n 200 /var/log/cloud-init-output.log
```

Use the serial console when SSH is unavailable.

### Terraform reports a state lock

First verify that no Terraform or Ansible deployment is still running. A lock must not be forced open while another process is using the state.

---

## Terraform and Ansible Workflow

The complete infrastructure workflow is divided into clear layers:

| Stage | Tool | Result |
|---|---|---|
| 1. Hypervisor preparation | Ansible | Installs and prepares libvirt, storage paths, permissions, and AppArmor access. |
| 2. Infrastructure provisioning | Terraform | Creates networks, pools, disks, cloud-init media, routers, and server VMs. |
| 3. Initial guest bootstrap | cloud-init | Configures the automation user, SSH, networking, swap, router VPN, and initial firewall. |
| 4. Service configuration | Ansible | Configures users, security, DNS, storage, databases, web services, monitoring, and backups. |
| 5. Ongoing operations | Terraform + Ansible | Terraform manages infrastructure changes; Ansible manages guest and service changes. |

This separation keeps the infrastructure reproducible while avoiding the use of Terraform as a general-purpose configuration management tool.
