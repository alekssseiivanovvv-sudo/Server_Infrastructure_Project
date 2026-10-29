 ## ⚙️ Distributed Automated Server Infrastructure Project

 A distributed infrastructure project built entirely with Infrastructure as Code & Open Source solutions.

 ## Table of Contents

- [Overview](#overview)
- [Documentation (WIP)](documentation/)

 ---

## Overview

An infrastructure lab distributed across two remote branches,
a cloud segment** and external DNS provider***. The project focuses on service availability, secure connectivity, data protection, centralized monitoring and automation.

Built as a college application servers project and portfolio project demonstrating practical skills in systems administration, DevOps, computer networking, and cybersecurity.
The documentation covers the architecture, deployment, and step-by-step manual configuration of servers and services.

> Actual work is done on two remotely located computers hosting all the infrastructure.
> 
> ** Cloud segment is simulated on one of the host computers by network segmentation.
> 
> *** External DNS segment is simulated on one of the host computers by network segmentation.

## Diagram
</div>

<img width="2591" height="2219" alt="Infra drawio (4)" src="https://github.com/user-attachments/assets/da575947-d420-40f8-8df1-61b0116ec1d9" />

---

<div align="left">

## Project Highlights

| Area | Implementation |
|---|---|
| Infrastructure as Code | Terraform, cloud-init, Ansible |
| Virtualization | KVM/QEMU and libvirt on two physical hosts |
| Networking | Routed branch networks connected through Tailscale |
| Database HA | PostgreSQL, Patroni and etcd |
| Distributed Storage | Three-node Garage S3 cluster |
| Web Availability | NGINX services behind HAProxy |
| Observability | Prometheus, Grafana, Loki and Telegram alerts |
| Backup | Restic backups stored on dedicated RAID1 volumes |
| Security | VPN-only administration, SSH keys, firewalling and local PKI |

## Failure Scenarios

- Loss of one branch: services continue through the remaining branch.
- Loss of cloud segment: Services continue working for clients, however automated management and monitoring would be unavailable.
- Loss of the PostgreSQL primary: Patroni promotes the replica; Service continues work.
- Loss of one Garage node: S3 data remains available through the cluster.
- Loss of a virtual machine: Terraform and Ansible can recreate its configuration.


## Stack

[![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)](https://www.linux.org/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![Alpine Linux](https://img.shields.io/badge/Alpine_Linux-0D597F?style=for-the-badge&logo=alpinelinux&logoColor=white)](https://alpinelinux.org/)
[![KVM](https://img.shields.io/badge/KVM-CC0000?style=for-the-badge&logo=linux&logoColor=white)](https://www.linux-kvm.org/)
[![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=for-the-badge&logo=ansible&logoColor=white)](https://www.ansible.com/)
[![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![HTML5](https://img.shields.io/badge/HTML5-E34F26?style=for-the-badge&logo=html5&logoColor=white)](https://developer.mozilla.org/en-US/docs/Web/HTML)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Patroni](https://img.shields.io/badge/Patroni-336791?style=for-the-badge&logoColor=white)](https://github.com/patroni/patroni)
[![NGINX](https://img.shields.io/badge/NGINX-009639?style=for-the-badge&logo=nginx&logoColor=white)](https://nginx.org/)
[![HAProxy](https://img.shields.io/badge/HAProxy-106DA9?style=for-the-badge&logo=haproxy&logoColor=white)](https://www.haproxy.org/)
[![Tailscale](https://img.shields.io/badge/Tailscale-242424?style=for-the-badge&logo=tailscale&logoColor=white)](https://tailscale.com/)
[![fail2ban](https://img.shields.io/badge/fail2ban-FF6600?style=for-the-badge&logo=linux&logoColor=white)](https://www.fail2ban.org/)
[![OpenSSH](https://img.shields.io/badge/OpenSSH-2C3E50?style=for-the-badge&logoColor=white)](https://www.openssh.com/)
[![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Grafana](https://img.shields.io/badge/Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white)](https://grafana.com/)
[![Telegram](https://img.shields.io/badge/Telegram-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://telegram.org/)
[![Garage](https://img.shields.io/badge/Garage-FF6B35?style=for-the-badge&logoColor=white)](https://garagehq.deuxfleurs.fr/)
[![restic](https://img.shields.io/badge/restic-4A90D9?style=for-the-badge&logo=restic&logoColor=white)](https://restic.net/)

</div>

---

## Skills Demonstrated

| Competency | What the Project Demonstrates |
|---|---|
| **Systems Engineering** | Designing a distributed infrastructure across two sites and a separate cloud segment |
| **DevOps and Automation** | Automated infrastructure deployment and service configuration with Ansible |
| **Infrastructure as Code** | Provisioning networks, storage volumes, virtual machines & cloud-init with Terraform |
| **Linux Administration** | Managing Ubuntu and Alpine Linux systems, users, permissions, packages, and services |
| **Network Engineering** | Network segmentation, routing, NAT, VPN, DNS, and firewall configuration |
| **Cybersecurity** | SSH key authentication, VPN access, firewalls, TLS, PKI, and access control |
| **Monitoring and Observability** | Collecting metrics and logs with Prometheus, Grafana, and Loki + Alerts via Telegram Bot
| **High Availability** | Load balancing, replication, health checks, and automatic service failover |
| **Database Administration** | PostgreSQL, Patroni, etcd, streaming replication, and automatic primary promotion |
| **Distributed Storage** | S3-compatible Garage storage and software RAID 1 |
| **Backup and Recovery** | Automated backups using Restic |
| **Scripting** | Bash, Python and HTML scripting |
| **Virtualization** | Working with KVM, QEMU, and libvirt | 
| **Containerization** | Deploying web services and infrastructure components with Docker |

## Authors

### Aleksei Ivanov - IT student

### Ilja Melikov - IT student
<div align="center">
Tallinn Technology College / Tallinna Tehnoloogiakolledž

2026
</div>
