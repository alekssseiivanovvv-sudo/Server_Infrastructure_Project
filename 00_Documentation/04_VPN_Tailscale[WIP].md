# VPN Connectivity with Tailscale
[![Tailscale](https://img.shields.io/badge/Tailscale-242424?style=for-the-badge&logo=tailscale&logoColor=white)](https://tailscale.com/)


Tailscale connects the remote laboratory hosts, the automation node and the three project networks through one private overlay network. The Alpine routers provide access to the virtual machines behind them, so each internal VM does not need its own Tailscale client. Administrators use the VPN to reach infrastructure across both physical hosts.

This chapter brings together the VPN steps from the Admin PC and router setup records. It covers device enrolment, subnet routing, tailnet policy, DNS integration and authentication key management. General KVM installation, full router firewall configuration and VS Code setup belong to their respective chapters.

## 1. Network layout

The connected-device screenshot records the following addresses. Earlier preparation screenshots used other administrator PC addresses; the table below follows the final machine list.

| Device | Tailscale IPv4 | Advertised project subnet | Role tag |
| --- | --- | --- | --- |
| cloud-router | 100.64.0.1 | 192.168.74.0/27 | tag:cloud-router |
| east-router | 100.64.0.2 | 192.168.72.0/27 | tag:east-router |
| west-router | 100.64.0.3 | 192.168.73.0/27 | tag:west-router |
| inet-dns | 100.100.200.200 | None | tag:inet-dns |
| frostylinux | 100.64.0.10 | None | Administrator PC and hypervisor |
| ilja-pc | 100.64.0.11 | None | Administrator PC and hypervisor |
| automation-node | 100.64.0.12 | None | Automation control node |

The router subnet prefixes are taken from the supplied tailnet policy. Each site's router is the gateway between its local LAN and the VPN. For example, a client reaching 192.168.73.0/27 uses west-router, while traffic to 192.168.72.0/27 uses east-router. The advertised prefixes and the 100.x Tailscale addresses serve different purposes.

<img width="2048" height="1025" alt="image" src="https://github.com/user-attachments/assets/806d34e4-046a-487c-9f13-3aaa0b8a928b" />


*Screenshot 01 — Connected project devices and their final Tailscale addresses.*

## 2. Administrator PC connection

On a supported Ubuntu or Kubuntu administrator PC, install the Tailscale client using the official installer and start interactive authentication:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Open the authentication URL printed by the client and approve the device in the project tailnet. The original preparation record shows a successful login for the device then named `frostyl`.

<img width="567" height="426" alt="image" src="https://github.com/user-attachments/assets/e63bcd1c-0b0e-4c2b-8449-a8f1a743b97a" />


*Screenshot 02 — Successful interactive authentication of the administrator PC.*

Linux clients must accept advertised subnet routes to reach the internal VM networks. Enable the project DNS settings as well:

```bash
sudo tailscale set --accept-routes=true --accept-dns=true
tailscale status
tailscale ip -4
```

The administrator PC addresses can be adjusted through **Machines → device menu → Edit machine IPv4**. The final addresses used in this chapter are 100.64.0.10 and 100.64.0.11.

## 3. Router authentication keys

Automated machine enrolment uses Tailscale authentication keys stored locally on **automation-node** and excluded from the repository. The repository documentation contains no actual enrolment key values. A Tailscale authentication key is separate from an administrator's OpenSSH private key.

The east-router example uses a reusable key, a 90-day enrolment validity period, a non-ephemeral device and the tag `tag:east-router`. The equivalent role tag is selected when preparing a key for another router.

<img width="692" height="1023" alt="image" src="https://github.com/user-attachments/assets/b41e78a9-b26c-4d7f-a43b-2e3a5b9521b6" />


*Screenshot 03 — Reusable tagged authentication key settings for the east router.*

The enrolment key's expiry and a registered device's node key expiry are separate settings. Expiry of an enrolment key prevents new enrolments with that key; it does not by itself disconnect devices already registered. The final machine list shows **Expiry disabled** on the tagged router and DNS devices.

## 4. Alpine router connection

Run the following commands as root on an Alpine router with the required package repositories configured:

```sh
apk update
apk add tailscale tailscale-openrc
modprobe tun
rc-update add tailscale default
rc-service tailscale start
```

For the manual test router, interactive enrolment was performed with:

```sh
tailscale up --hostname=test-router
```

This test is separate from the final tagged routers. Its temporary address is not part of the final addressing plan. The screenshot shows a successful connection and a warning that subnet routes are not yet accepted.

<img width="1937" height="117" alt="image" src="https://github.com/user-attachments/assets/9617e06b-5e04-4ed4-824e-f596ed0b3c6c" />


*Screenshot 04 — Manual test router connected to the tailnet before subnet route acceptance.*

Enable persistent IPv4 forwarding on a router:

```sh
mkdir -p /etc/sysctl.d
printf 'net.ipv4.ip_forward = 1\n' > /etc/sysctl.d/99-router.conf
rc-update add sysctl boot
sysctl -p /etc/sysctl.d/99-router.conf
```

<img width="1012" height="69" alt="image" src="https://github.com/user-attachments/assets/ccf33a81-45af-4409-a580-8c3848328e23" />


*Screenshot 05 — IPv4 forwarding enabled on the Alpine test router.*

After enrolment with the appropriate tagged key, each project router advertises its own LAN and accepts remote site routes. These are the reference settings for site-to-site operation; the supplied screenshots do not show every runtime flag:

```sh
# Run only on east-router
tailscale set --advertise-routes=192.168.72.0/27 --accept-routes=true --snat-subnet-routes=false

# Run only on west-router
tailscale set --advertise-routes=192.168.73.0/27 --accept-routes=true --snat-subnet-routes=false

# Run only on cloud-router
tailscale set --advertise-routes=192.168.74.0/27 --accept-routes=true --snat-subnet-routes=false
```

For LAN-to-LAN routing, disabling subnet SNAT preserves the original source address. Internal VMs need a return path through their local router, including routes back to remote LANs and Tailscale clients. The firewall must allow forwarding between the LAN interface and `tailscale0`. These requirements must be checked on the running routers; a **Connected** status alone does not verify them.

## 5. Tags and automatic route approval

`tagOwners` defines who may assign each infrastructure tag. The `autoApprovers.routes` section permits the corresponding tagged router to advertise its site's subnet without a separate manual approval step. It does not advertise a route by itself and does not grant permission to send application traffic.

The `nodeAttrs.ipPool` entries assign a separate /32 pool to each router role and to inet-dns. Each role is intended for one active device. A recreated device cannot share an already occupied address with its old registration; stale registrations need to be reviewed when rebuilding machines.

If an already advertised route remains unapproved, review it under the device's subnet settings. Adding an auto-approval rule does not retroactively approve an existing unapproved advertisement.

<img width="1323" height="537" alt="image" src="https://github.com/user-attachments/assets/90e24c78-8463-4a67-be92-037ebab21a47" />


## 6. DNS integration

The supplied DNS screenshot shows MagicDNS together with two split DNS scopes:

| Scope | Resolver addresses | Purpose |
| --- | --- | --- |
| Tailnet MagicDNS | 100.100.100.100 | Tailscale device names |
| project.local | 100.64.0.1, 100.64.0.2, 100.64.0.3 | Internal project DNS through the routers |
| shop.project.local | 100.100.200.200 | Dedicated shop DNS through inet-dns |

<img width="943" height="417" alt="image" src="https://github.com/user-attachments/assets/6c12d69c-391f-4bda-809d-87f3dec7ee70" />

*Screenshot 06 — MagicDNS and split DNS settings for the project.*

`100.100.100.100` is the Tailscale resolver, while `100.100.200.200` is the project's separate inet-dns device. MagicDNS registers tailnet device names; the custom `project.local` records are provided by the configured project DNS services.

The more specific `shop.project.local` scope directs matching queries to inet-dns. This split DNS setting selects a resolver; it does not create the shop's A records or configure HTTP load balancing. The three resolvers for `project.local` must provide consistent records; their displayed order is not a primary and backup priority.

For this setup to work, clients must accept Tailscale DNS settings, and the selected DNS services must listen on reachable addresses and allow both UDP and TCP port 53 from the VPN. The screenshot documents the resolver configuration, not a completed DNS reachability test. Existing lab names use `.local`, which can conflict with mDNS on some clients.

## 7. Access policy and SSH

The current `grants` rule permits all sources, destinations and IP traffic within the tailnet. The lab therefore uses a permissive VPN policy; its tags identify device roles and support provisioning, rather than isolating the sites. Router and server firewalls remain separate controls.

The supplied policy also retains a default Tailscale SSH rule with `action: check`, `autogroup:self` and the usernames `autogroup:nonroot` and `root`. This rule applies to Tailscale SSH when that feature is enabled on a destination. It does not enable SSH on a device or override the project's OpenSSH configuration.

Project administration uses ordinary OpenSSH accounts and keys over the VPN, with port 2222 on the configured infrastructure servers. A `root` entry in the separate Tailscale SSH policy is not evidence that OpenSSH root login is enabled. Restricting the permissive tailnet policy is a possible future hardening step.

## 8. Optional app connector entry

The supplied policy and preparation screenshot include an app named `grafana`, the domain `east-west.grafana.com` and `tag:cloud-router` as its connector selector.

<img width="728" height="917" alt="image" src="https://github.com/user-attachments/assets/171f61fd-0f57-4ba2-bded-43307cb8e819" />


*Screenshot 07 — Optional Grafana app connector configuration in the administration console.*

An app connector routes traffic for configured application domains. Adding this entry does not host Grafana, create a DNS record, prove ownership of the domain or publish a service with Tailscale Serve or Funnel. The supplied material does not demonstrate a working application connection, so this entry is recorded as an optional configuration rather than a verified monitoring access path.

## 9. Current key management and deferred automation

In the implemented workflow, enrolment keys are prepared in advance and kept locally on automation-node, outside the committed repository content. Automation uses these existing keys when registering machines.

Generating a new authentication key automatically for each machine creation was considered during project planning. This improvement was deferred because of the time limit for the assignment. A future implementation could request a short-lived, tagged, single-use key through the Tailscale API using a suitably scoped credential, pass it to provisioning without logging it and handle failed deployments and key cleanup. This lifecycle is not implemented in the current project.

## 10. Evidence and operational checks

The screenshots show successful client enrolment, configured key options, IPv4 forwarding, the final connected-device list and the DNS settings. They do not establish successful traffic forwarding between every subnet or complete failover testing.

Useful checks after deployment are shown below. These are verification commands, not additional recorded test results:

```bash
tailscale status
tailscale ping 100.64.0.3
ping -c 3 192.168.73.1
getent hosts shop.project.local
```

This design has one router per site subnet. The east, west and cloud routers advertise different prefixes, so they are not redundant replacements for one another. Loss of a site's only router removes that site's VPN path even if services in another site remain available.

## Appendix A. Documented tailnet policy

This is the supplied policy with comments removed and the owner's email replaced by `owner@example.com` for publication. Replace this placeholder with the actual tailnet owner before using the policy. The optional app connector entry and permissive access rule are preserved to reflect the supplied configuration.

```json
{
  "grants": [
    { "src": ["*"], "dst": ["*"], "ip": ["*"] }
  ],
  "ssh": [
    {
      "action": "check",
      "src": ["autogroup:member"],
      "dst": ["autogroup:self"],
      "users": ["autogroup:nonroot", "root"]
    }
  ],
  "tagOwners": {
    "tag:cloud-router": ["owner@example.com"],
    "tag:east-router": ["owner@example.com"],
    "tag:west-router": ["owner@example.com"],
    "tag:inet-dns": ["owner@example.com"]
  },
  "nodeAttrs": [
    { "target": ["tag:cloud-router"], "ipPool": ["100.64.0.1/32"] },
    { "target": ["tag:east-router"], "ipPool": ["100.64.0.2/32"] },
    { "target": ["tag:west-router"], "ipPool": ["100.64.0.3/32"] },
    { "target": ["tag:inet-dns"], "ipPool": ["100.100.200.200/32"] },
    {
      "target": ["*"],
      "app": {
        "tailscale.com/app-connectors": [
          {
            "name": "grafana",
            "connectors": ["tag:cloud-router"],
            "domains": ["east-west.grafana.com"]
          }
        ]
      }
    }
  ],
  "autoApprovers": {
    "routes": {
      "192.168.74.0/27": ["tag:cloud-router"],
      "192.168.72.0/27": ["tag:east-router"],
      "192.168.73.0/27": ["tag:west-router"]
    }
  },
  "ipsets": {}
}
```

## References

- [Tailscale subnet routers](https://tailscale.com/docs/features/subnet-routers)
- [Tailscale site-to-site networking](https://tailscale.com/docs/features/site-to-site)
- [Tailnet policy syntax and auto approvers](https://tailscale.com/docs/reference/syntax/policy-file)
- [IP pool configuration](https://tailscale.com/docs/reference/ip-pool)
- [DNS configuration](https://tailscale.com/docs/reference/dns)
- [Authentication keys](https://tailscale.com/docs/features/access-control/auth-keys)
- [Tailscale SSH](https://tailscale.com/docs/features/tailscale-ssh)
- [App connectors](https://tailscale.com/docs/features/app-connectors)

