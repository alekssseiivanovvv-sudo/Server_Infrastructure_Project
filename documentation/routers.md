# Manual Alpine Linux Router Installation and Configuration

## Overview

This guide documents the manual installation and configuration of an Alpine Linux virtual router used in the distributed infrastructure project. Dedicated routers make the laboratory topology closer to a real multi-site environment by separating WAN, LAN and VPN traffic instead of connecting every service VM directly to the external network.

OpenWrt was considered initially because it provides a ready-made open-source router platform. Alpine Linux was selected instead because it is lightweight, supports cloud-init and standard Linux automation, and can run the same networking components that are later managed through Terraform and Ansible. The router provides SSH administration, Tailscale site-to-site connectivity, nftables filtering and NAT, dnsmasq name resolution, and Fail2ban protection.

### Virtual machine specification

| Resource | Value |
|---|---:|
| CPU | 1 vCPU |
| Memory | 512 MB RAM |
| System disk | 5 GB |
| Operating system | Alpine Linux 3.24.3 |
| WAN interface | `eth0`, DHCP |
| LAN interface | `eth1`, static address |
| VPN interface | `tailscale0` |

The example below configures the east-site router with LAN address `192.168.72.1/27`. The west and cloud routers use the same procedure with their own subnets.

| Router | LAN address | Advertised subnet | Tailscale address |
|---|---:|---:|---:|
| `east-router` | `192.168.72.1/27` | `192.168.72.0/27` | `100.64.0.2` |
| `west-router` | `192.168.73.1/27` | `192.168.73.0/27` | `100.64.0.3` |
| `cloud-router` | `192.168.74.1/27` | `192.168.74.0/27` | `100.64.0.1` |

> **Safety note:** Perform firewall changes through the virtual machine console. The final rules allow SSH only through `tailscale0`; applying them before Tailscale is connected can terminate a WAN SSH session.

## 1. Prepare the Tailscale policy

The tailnet policy assigns stable Tailscale addresses to tagged routers and automatically approves the three advertised LAN routes. This prevents manual route approval after every rebuild.

```json
"nodeAttrs": [
  {
    "target": ["tag:cloud-router"],
    "ipPool": ["100.64.0.1/32"]
  },
  {
    "target": ["tag:east-router"],
    "ipPool": ["100.64.0.2/32"]
  },
  {
    "target": ["tag:west-router"],
    "ipPool": ["100.64.0.3/32"]
  }
],
"autoApprovers": {
  "routes": {
    "192.168.74.0/27": ["tag:cloud-router"],
    "192.168.72.0/27": ["tag:east-router"],
    "192.168.73.0/27": ["tag:west-router"]
  }
}
```

![Screenshot 01 - Tailscale ACL policy with router addresses and route approvers](images/router-setup/screenshot-01.png)

**Screenshot 01 note:** The complete policy must also contain tag ownership and access grants. The screenshot shows only the address assignment and route approval section.

## 2. Boot the Alpine installer

Attach the Alpine virtual ISO to the router VM and start it from the virtual CD-ROM. The bootloader starts the Alpine live environment automatically.

<img width="940" height="671" alt="image" src="https://github.com/user-attachments/assets/d93e4799-89d3-4997-8caa-8aa9c29166f5" />


<img width="940" height="708" alt="image" src="https://github.com/user-attachments/assets/97b3790f-1b99-4937-acd6-894cb6b34a5e" />


Log in as `root`; the live environment initially has no root password. Start the installer:

```sh
setup-alpine
```

<img width="940" height="267" alt="image" src="https://github.com/user-attachments/assets/990933c1-4be4-4aa0-86a1-9b9dfe1870e6" />


Select the keyboard layout and continue through the installer prompts.

<img width="940" height="406" alt="image" src="https://github.com/user-attachments/assets/1416ef11-9ac5-4260-bc25-a76790ce3125" />


Set the hostname, configure `eth0` with DHCP, and leave advanced manual networking for the installed system. Set a root password when requested.

![Screenshot 04 - Hostname and interface configuration](images/router-setup/screenshot-04.png)

Select `Europe/Tallinn` as the time zone.

<img width="940" height="335" alt="image" src="https://github.com/user-attachments/assets/b260ba71-3f10-4da0-b75d-16bc7fcb2794" />


Complete the installation to the system disk, shut down the VM, detach the ISO, and boot from the installed disk.

## 3. Configure WAN and LAN interfaces

Open the interface configuration:

```sh
vi /etc/network/interfaces
```

For the east router, use:

```text
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet static
    address 192.168.72.1
    netmask 255.255.255.224
```

<img width="940" height="802" alt="image" src="https://github.com/user-attachments/assets/09222d14-f4b0-4ee4-bde2-c30202e01d1f" />


Apply the configuration:

```sh
rc-service networking restart
```

Verify both interfaces and the default route:

```sh
ip -br address
```

```sh
ip route
```

<img width="940" height="894" alt="image" src="https://github.com/user-attachments/assets/913c8219-e9a5-472a-b9ef-adc0098518e0" />


Expected result:

- `eth0` receives a WAN address from the libvirt `default` network.
- `eth1` uses `192.168.72.1/27`.
- The default route is learned through `eth0`.

## 4. Enable the Alpine package repositories

An installation started from an ISO may leave `/etc/apk/repositories` pointing only to `/media/cdrom/apks`. Replace it with the official `main` and `community` repositories:

```sh
printf 'https://dl-cdn.alpinelinux.org/alpine/v3.24/main\nhttps://dl-cdn.alpinelinux.org/alpine/v3.24/community\n' > /etc/apk/repositories
```

Refresh the package indexes:

```sh
apk update
```

<img width="940" height="138" alt="image" src="https://github.com/user-attachments/assets/7f1dbf0e-9c7f-47e4-baff-2ab67d123bc7" />


## 5. Install and connect Tailscale

Check free space before installing additional packages:

```sh
df -h /
```

Install Tailscale and its OpenRC service:

```sh
apk add tailscale tailscale-openrc
```

```sh
modprobe tun
```

```sh
rc-update add tailscale default
```

```sh
rc-service tailscale start
```

For a first interactive connection:

```sh
tailscale up --hostname=test-router --accept-dns=false
```

Open the displayed authentication URL and approve the device.

<img width="940" height="492" alt="image" src="https://github.com/user-attachments/assets/8732744e-231f-40f3-84db-d6b9a3995808" />


Verify the connection:

```sh
tailscale status
```

```sh
tailscale ip -4
```

Configure the router as a subnet router. The east-site command is:

```sh
tailscale set --hostname=east-router --advertise-routes=192.168.72.0/27 --accept-routes=true --snat-subnet-routes=false --accept-dns=false
```

Use `192.168.73.0/27` for the west router and `192.168.74.0/27` for the cloud router. Tailscale SNAT is disabled so that hosts at other sites retain the original source address. Internet NAT remains a separate nftables rule on `eth0`.

## 6. Install the routing and security packages

Install nftables, dnsmasq, Fail2ban and the text editor:

```sh
apk add nftables nftables-openrc dnsmasq fail2ban nano
```

<img width="940" height="900" alt="image" src="https://github.com/user-attachments/assets/be170480-096c-4b21-af6d-a3e62fda23df" />


## 7. Enable IPv4 forwarding

Create the persistent kernel configuration:

```sh
install -d -m 0755 /etc/sysctl.d
```

```sh
printf 'net.ipv4.ip_forward = 1\n' > /etc/sysctl.d/99-router.conf
```

```sh
rc-update add sysctl boot
```

Apply and verify it:

```sh
sysctl -p /etc/sysctl.d/99-router.conf
```

```sh
sysctl net.ipv4.ip_forward
```

<img width="940" height="65" alt="image" src="https://github.com/user-attachments/assets/ca2f0baf-2897-444f-848b-9bc1b05aef7d" />


<img width="940" height="138" alt="image" src="https://github.com/user-attachments/assets/547cd9b4-a14d-4577-8b3f-735d56ca3c67" />


The expected value is `net.ipv4.ip_forward = 1`.

## 8. Configure nftables firewall and NAT

Back up the existing rules before replacing the file:

```sh
cp /etc/nftables.nft /etc/nftables.nft.bak
```

Open the configuration:

```sh
vi /etc/nftables.nft
```

Use the following rules for the east router. Port `2222` is the hardened project SSH port.

```nft
#!/usr/sbin/nft -f

destroy table inet lab_router

table inet lab_router {
    set project_lans {
        type ipv4_addr
        flags interval
        elements = { 192.168.72.0/27, 192.168.73.0/27, 192.168.74.0/27 }
    }

    chain input {
        type filter hook input priority 0; policy drop;

        iifname != "tailscale0" tcp dport { 22, 2222 } drop
        ct state invalid drop
        ct state established,related accept
        iifname "lo" accept
        meta l4proto { icmp, ipv6-icmp } accept

        iifname "tailscale0" tcp dport 2222 accept
        iifname "eth0" udp sport 67 udp dport 68 accept
        iifname "eth0" udp dport 41641 accept

        iifname "eth1" ip saddr 192.168.72.0/27 ip daddr 192.168.72.1 udp dport 53 accept
        iifname "eth1" ip saddr 192.168.72.0/27 ip daddr 192.168.72.1 tcp dport 53 accept

        ip saddr 192.168.74.3 tcp dport 9100 accept
        iifname "tailscale0" tcp dport 9100 accept
    }

    chain mangle_forward {
        type filter hook forward priority mangle; policy accept;
        oifname "tailscale0" tcp flags syn tcp option maxseg size set rt mtu
    }

    chain forward {
        type filter hook forward priority 0; policy drop;

        ct state invalid drop
        ct state established,related accept
        iifname "eth1" oifname "eth0" ip saddr 192.168.72.0/27 accept
        iifname "eth1" oifname "tailscale0" ip saddr 192.168.72.0/27 accept
        iifname "tailscale0" oifname "eth1" ip daddr 192.168.72.0/27 accept
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "eth0" ip saddr 192.168.72.0/27 masquerade
    }
}
```

<img width="940" height="860" alt="image" src="https://github.com/user-attachments/assets/67f2e452-0743-4dae-bbd3-7fff1f590eaa" />


Check the syntax before applying anything:

```sh
nft -c -f /etc/nftables.nft
```

Enable and restart nftables:

```sh
rc-update add nftables boot
```

```sh
rc-service nftables restart
```

<img width="940" height="65" alt="image" src="https://github.com/user-attachments/assets/57a320ac-3d05-432c-a276-ad378ef5b7dc" />


Display the loaded table:

```sh
nft list table inet lab_router
```

<img width="940" height="821" alt="image" src="https://github.com/user-attachments/assets/48cb9e81-e11d-4c3f-a47b-52e84d93fe66" />


Verify Internet NAT separately:

```sh
nft list chain inet lab_router postrouting
```

<img width="940" height="146" alt="image" src="https://github.com/user-attachments/assets/38c748ca-4a4d-4512-8c02-eca7d4885ca8" />


The `masquerade` rule is intentionally attached to `eth0`, because that interface receives the external address. No Internet NAT is applied to `tailscale0`.

## 9. Configure dnsmasq

Open the configuration:

```sh
vi /etc/dnsmasq.conf
```

```ini
domain-needed
bogus-priv
no-resolv
no-hosts

domain=project.local
local=/project.local/

interface=lo
interface=eth1
listen-address=127.0.0.1
listen-address=192.168.72.1
bind-interfaces

cache-size=1000

server=1.1.1.1
server=9.9.9.9

host-record=east-router.project.local,east-router,192.168.72.1
host-record=east-load-balancer.project.local,east-load-balancer,192.168.72.2
host-record=east-web.project.local,east-web,192.168.72.3
host-record=east-db.project.local,east-db,192.168.72.4
host-record=east-storage.project.local,east-storage,192.168.72.5

host-record=west-router.project.local,west-router,192.168.73.1
host-record=west-load-balancer.project.local,west-load-balancer,192.168.73.2
host-record=west-web.project.local,west-web,192.168.73.3
host-record=west-db.project.local,west-db,192.168.73.4
host-record=west-storage.project.local,west-storage,192.168.73.5

host-record=cloud-router.project.local,cloud-router,192.168.74.1
host-record=cloud-monitoring.project.local,cloud-monitoring,192.168.74.3
host-record=cloud-quorum.project.local,cloud-quorum,192.168.74.5
host-record=cloud-s3.project.local,cloud-s3,192.168.74.6

host-record=monitoring.project.local,grafana.project.local,prometheus.project.local,loki.project.local,192.168.74.3
host-record=quorum.project.local,192.168.74.5
host-record=s3.project.local,192.168.74.6
host-record=shop.project.local,load-balancer.project.local,lb.project.local,192.168.72.2
```

<img width="940" height="790" alt="image" src="https://github.com/user-attachments/assets/f50a2d96-6576-45ea-aad9-74b209290482" />


Check the file:

```sh
dnsmasq --test --conf-file=/etc/dnsmasq.conf
```

<img width="940" height="206" alt="image" src="https://github.com/user-attachments/assets/4cff2886-749e-4903-913e-d7ba9b9e3031" />


**Troubleshooting:** The first check in Screenshot 22 failed because a Markdown code-fence line was pasted into the configuration. Remove lines such as ` ```ini ` or ` ``` ` from the actual file. A valid test ends with `dnsmasq: syntax check OK`.

Enable and start the service:

```sh
rc-update add dnsmasq default
```

```sh
rc-service dnsmasq restart
```

```sh
rc-service dnsmasq status
```

<img width="940" height="242" alt="image" src="https://github.com/user-attachments/assets/2d22cae8-d674-454d-aac7-0c0e73c768ca" />


## 10. Configure the router resolver

Tailscale can overwrite `/etc/resolv.conf` when MagicDNS is accepted. Disable DNS takeover on the router before pointing it to the local dnsmasq instance:

```sh
tailscale set --accept-dns=false
```

```sh
printf 'search project.local\nnameserver 127.0.0.1\n' > /etc/resolv.conf
```

Verify the file:

```sh
cat /etc/resolv.conf
```

Test internal and external resolution:

```sh
nslookup east-db.project.local 127.0.0.1
```

```sh
nslookup alpine.org 127.0.0.1
```

```sh
nslookup shop.project.local 127.0.0.1
```

<img width="940" height="831" alt="image" src="https://github.com/user-attachments/assets/5fc9dad7-e083-490b-a263-0e3b34d7e3c9" />

**Screenshot 24 note:** The screenshot shows Tailscale-generated nameservers still present in `/etc/resolv.conf`, although explicit queries to `127.0.0.1` already work. Running `tailscale set --accept-dns=false` prevents Tailscale from replacing the router's local resolver configuration.

## 11. Configure Fail2ban for SSH

Ensure system logging is enabled:

```sh
rc-update add syslog boot
```

```sh
rc-service syslog start
```

Verify that the Alpine SSH filter exists:

```sh
ls -l /etc/fail2ban/filter.d/alpine-sshd.conf
```

Create the jail directory and configuration:

```sh
mkdir -p /etc/fail2ban/jail.d
```

```sh
vi /etc/fail2ban/jail.d/sshd.local
```

```ini
[sshd]
enabled = true
filter = alpine-sshd
port = 2222
backend = polling
logpath = /var/log/messages
maxretry = 5
findtime = 10m
bantime = 1h
banaction = nftables-multiport
```

<img width="940" height="829" alt="image" src="https://github.com/user-attachments/assets/fe60bfa9-49cf-4d66-b897-0b9502d7c492" />


Validate and start Fail2ban:

```sh
fail2ban-client -t
```

```sh
rc-update add fail2ban default
```

```sh
rc-service fail2ban restart
```

```sh
fail2ban-client status sshd
```

<img width="940" height="438" alt="image" src="https://github.com/user-attachments/assets/c855301a-d01c-4b3a-8ca4-65464455fd1e" />


Fail2ban is a defense-in-depth measure. The primary SSH controls remain key-only authentication, the custom SSH port, Tailscale ACLs, and nftables rules that reject SSH from non-VPN interfaces.

## 12. Final verification

Run the following checks on the router:

```sh
ip -br address
```

```sh
ip route
```

```sh
tailscale status
```

```sh
sysctl net.ipv4.ip_forward
```

```sh
nft list table inet lab_router
```

```sh
rc-service nftables status
```

```sh
rc-service dnsmasq status
```

```sh
rc-service fail2ban status
```

```sh
nslookup shop.project.local 127.0.0.1
```

From an east-site LAN server, verify the gateway, Internet access and DNS:

```sh
ip route
```

```sh
ping -c 3 192.168.72.1
```

```sh
ping -c 3 1.1.1.1
```

```sh
nslookup shop.project.local 192.168.72.1
```

Successful Internet access from the LAN confirms IPv4 forwarding, the `forward` rules, and WAN masquerading. Successful `project.local` lookups confirm dnsmasq and the LAN DNS firewall rules.

## Automation counterpart

The manual procedure demonstrates the configuration that is later maintained automatically:

- Terraform and cloud-init create the router VM, configure interfaces, install Tailscale, and establish the initial firewall.
- Ansible playbook `03_FIREWALL_DNS.yml` applies the `router_firewall` and `router_dns` roles.
- The Ansible nftables template keeps NAT on the WAN interface and allows site-to-site routing through Tailscale.
- The dnsmasq template generates inventory-backed `project.local` records.

## References

- [Alpine Linux setup scripts](https://wiki.alpinelinux.org/wiki/Alpine_configuration_management_scripts)
- [Alpine Linux package repositories](https://wiki.alpinelinux.org/wiki/Repositories)
- [Tailscale subnet routers](https://tailscale.com/docs/features/subnet-routers)
- [Tailscale DNS and resolv.conf](https://tailscale.com/docs/reference/faq/dns-resolv-conf)
- [nftables NAT documentation](https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_%28NAT%29)
- [Alpine Linux Fail2ban documentation](https://wiki.alpinelinux.org/wiki/Fail2ban)
