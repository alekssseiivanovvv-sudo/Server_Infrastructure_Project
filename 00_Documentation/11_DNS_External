# External DNS Failover for the Shop

## Overview

The external DNS server gives users one name for the shop, `shop.project.local`, and decides which site should receive traffic. It answers with the address of every **healthy** site load balancer and removes a site from the answer when its HAProxy fails its health check.

| Item | Value |
|---|---|
| Host | `inet-dns` |
| Address | `100.100.200.200` |
| OS | Alpine Linux, 512 MiB RAM, 5 GiB disk |
| Network | libvirt `default` network (outside the project LANs), Tailscale for administration |
| Software | dnsmasq + a small health-check service |

```text
                 ┌──────────────────────────────┐
 client ── DNS ─►│ inet-dns  (dnsmasq)          │
                 │  /var/lib/external-dns/      │
                 │        shop.hosts            │
                 └──────────▲───────────────────┘
                            │ rewrites file when health changes
                 ┌──────────┴───────────┐
                 │ external-dns-healthcheck (every 10 s)
                 └───────┬───────────────┬──────┘
          GET /health    │               │    GET /health
              east HAProxy 192.168.72.2   west HAProxy 192.168.73.2
```

### Records published

| Name | Points to |
|---|---|
| `shop.project.local` | all healthy HAProxy nodes |
| `lb.project.local` | all healthy HAProxy nodes |
| `load-balancer.project.local` | all healthy HAProxy nodes |

With both sites healthy, clients receive two A records. If one site fails, only the surviving address is returned.

### Design decisions

- **DNS-level failover.** The sites are independent networks, so a client-side name that follows health is simpler than a shared virtual IP.
- **Short TTL (10 s).** Clients stop using a failed site within seconds. Failover is not instant: it takes up to three HAProxy-style detection cycles plus the TTL.
- **No upstream recursion for project names.** dnsmasq is authoritative for `project.local` and forwards anything else to `1.1.1.1` and `9.9.9.9`.
- **Hosts file as state.** The health checker only writes `/var/lib/external-dns/shop.hosts`, and dnsmasq reloads when it changes.
- **Seed once.** The initial file lists both sites, but later runs of Ansible do not overwrite the live state (`force: false`).

## Prerequisites

- Alpine VM `inet-dns` joined to Tailscale (created by Terraform, see [01_Terraform.md](01_Terraform.md)).
- Both site HAProxy nodes running and answering `GET /health`.
- Root or `sudo` access.

## 1. Install packages

```sh
sudo apk update
sudo apk add dnsmasq curl
sudo mkdir -p /var/lib/external-dns
```

## 2. Create the initial record file

`/var/lib/external-dns/shop.hosts`:

```text
192.168.72.2 shop.project.local load-balancer.project.local lb.project.local
192.168.73.2 shop.project.local load-balancer.project.local lb.project.local
```

## 3. Configure dnsmasq

`/etc/dnsmasq.conf`:

```ini
domain-needed
bogus-priv
no-resolv
no-hosts

domain=project.local
local=/project.local/

listen-address=127.0.0.1
listen-address=100.100.200.200
bind-dynamic

cache-size=1000
local-ttl=10
addn-hosts=/var/lib/external-dns/shop.hosts

server=1.1.1.1
server=9.9.9.9
```

| Option | Purpose |
|---|---|
| `no-resolv`, `no-hosts` | Ignore local resolver and `/etc/hosts` |
| `local=/project.local/` | Answer the domain locally, never forward it |
| `addn-hosts` | Load the health-driven record file |
| `local-ttl=10` | 10-second TTL for fast failover |
| `bind-dynamic` | Start even if the Tailscale address appears later |

Test the syntax:

```sh
sudo dnsmasq --test --conf-file=/etc/dnsmasq.conf
sudo rc-update add dnsmasq default
sudo rc-service dnsmasq start
```

## 4. Create the health-check script

`/usr/local/sbin/external-dns-healthcheck`:

```sh
#!/bin/sh
set -eu

HOSTS_FILE=/var/lib/external-dns/shop.hosts
TEMP_FILE="${HOSTS_FILE}.tmp"
DNS_NAMES='shop.project.local load-balancer.project.local lb.project.local'

update_records() {
    : > "${TEMP_FILE}"

    if curl --silent --show-error --fail --max-time 3 --output /dev/null \
        'http://192.168.72.2/health'; then
        printf '%s %s\n' '192.168.72.2' "${DNS_NAMES}" >> "${TEMP_FILE}"
    fi

    if curl --silent --show-error --fail --max-time 3 --output /dev/null \
        'http://192.168.73.2/health'; then
        printf '%s %s\n' '192.168.73.2' "${DNS_NAMES}" >> "${TEMP_FILE}"
    fi

    if ! cmp -s "${TEMP_FILE}" "${HOSTS_FILE}"; then
        mv "${TEMP_FILE}" "${HOSTS_FILE}"
        rc-service dnsmasq reload >/dev/null 2>&1 || \
            rc-service dnsmasq restart >/dev/null 2>&1
    else
        rm -f "${TEMP_FILE}"
    fi
}

trap 'rm -f "${TEMP_FILE}"' EXIT INT TERM

while true; do
    update_records
    sleep 10
done
```

```sh
sudo chmod 755 /usr/local/sbin/external-dns-healthcheck
```

The script builds a new file from scratch each cycle and replaces the live one only if it differs, so dnsmasq is reloaded only on a real change.

> **Behaviour when both sites fail:** the file becomes empty and the name stops resolving, which is an honest failure rather than a stale answer.

## 5. Create the OpenRC service

`/etc/init.d/external-dns-healthcheck`:

```sh
#!/sbin/openrc-run

name="External DNS HAProxy health checker"
description="Updates shop DNS records from HAProxy health checks"
command="/usr/local/sbin/external-dns-healthcheck"
command_background="yes"
pidfile="/run/${RC_SVCNAME}.pid"

depend() {
    need net dnsmasq
    after tailscale
}
```

```sh
sudo chmod 755 /etc/init.d/external-dns-healthcheck
sudo rc-update add external-dns-healthcheck default
sudo rc-service external-dns-healthcheck start
```

## 6. Firewall

The host firewall opens DNS on the external node:

```nft
udp dport 53 accept
tcp dport 53 accept
```

SSH remains limited to the Tailscale address (see [03_Security.md](03_Security.md)).

## 7. Verification

```sh
nslookup shop.project.local 127.0.0.1
cat /var/lib/external-dns/shop.hosts
```

With both sites healthy, two addresses are returned.

### Failover test

On the east load balancer, stop HAProxy:

```sh
sudo rc-service haproxy stop     # Alpine
# or: sudo systemctl stop haproxy  (Ubuntu)
```

Within about 10-15 seconds:

```sh
nslookup shop.project.local 100.100.200.200
```

The east address disappears. Start HAProxy again and it returns after the next successful check.

## Ansible Automation

| Step | Ansible action |
|---|---|
| Safety checks | Alpine, exactly one DNS node, two HAProxy nodes |
| Packages | `dnsmasq`, `curl` |
| State directory | `/var/lib/external-dns` |
| Seed records | `shop.hosts` template, `force: false` |
| Configuration | `dnsmasq.conf` with `dnsmasq --test` validation |
| Health checker | Script and OpenRC service from templates |
| Services | Enable and start both |
| Verification | Waits for port 53, retries `nslookup` |

Run it (third play of the shop playbook):

```sh
cd 02_Ansible
ansible-playbook 06_WEB_HAPROXY_DNS_service.yml --ask-vault-pass --limit inet_dns_servers
```

Defaults such as the DNS names, TTL (`external_dns_ttl`) and check interval (`external_dns_check_interval`) are in `roles/external_dns/defaults/main.yml`.

## Relationship to the Internal DNS

This server is separate from the project's internal DNS. Each site router runs its own dnsmasq for `project.local` host names such as `east-db.project.local`, and clients select the router of their own site (`project_dns_client` role). The external server handles only the public shop entry point and the name of the DNS node itself.

## Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| Name does not resolve | Both sites unhealthy or file empty | `cat /var/lib/external-dns/shop.hosts` |
| Site never removed | Health checker stopped | `rc-service external-dns-healthcheck status` |
| Site never returns | `/health` returns 503 | `curl -i http://<haproxy>/health` |
| `dnsmasq` fails to start | Syntax error | `dnsmasq --test` |
| Works locally, not remotely | Firewall or listen address | `ss -lunp \| grep :53`, `nft list ruleset` |
| Stale answers | Client cache | Wait for 10 s TTL |

## Result

Users resolve one name that automatically follows the healthy sites. Failure detection and record updates run on a 10-second cycle, the state is a single readable file, and the setup is fully reproducible with Ansible.
