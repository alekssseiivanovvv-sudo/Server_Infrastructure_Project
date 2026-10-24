# ⚙️ Distributed Automated Server Infrastructure Project

 A distributed infrastructure project built entirely with Infrastructure as Code & Open Source solutions.

 ## 📑 Table of Contents

- [Overview](#-overview)
- [Documentation](#-documentation) (WIP)

 ---

## 📖 Overview

This project is a reference implementation of a distributed, highly available IT infrastructure designed to demonstrate practical DevOps, SysAdmin, and Infrastructure Engineering skills.

The infrastructure models a hybrid environment consisting of two geographically separated office branches and a cloud data center. Each branch contains an equivalent set of services, while the cloud segment provides shared infrastructure, routing, load balancing, monitoring, and quorum components.

> 🎯 **Goal:** Build a resilient, observable, and partially self-healing infrastructure stack using open-source and free technologies.


The architecture is designed around the following principles:

1. **High availability**  
   Both branches are capable of serving user requests. Traffic is distributed between them to improve availability, throughput, and response times.

2. **Fault tolerance**  
   The web service is designed to remain operational if one branch or cloud components become unavailable.

3. **Resilience**  
   Infrastructure and services are deployed and configured using Infrastructure as Code, allowing failed components to be recreated and restored consistently.

4. **Observability**  
   Infrastructure health, system metrics, logs, and service availability are monitored through a centralized monitoring stack.

5. **Security**  
   Administrative access is restricted through VPN-based connectivity, controlled firewall rules, SSH key authentication, TLS certificates, and dedicated service accounts.

6. **Automation**  
   Ansible and Terraform are used to automate infrastructure provisioning, system configuration, service deployment, and recovery operations.



## Diagram
</div>

<img width="2591" height="2219" alt="Infra drawio (3)" src="https://github.com/user-attachments/assets/f4f3ea2f-8fe7-4afc-89ac-341bbe6cd27e" />

---

<div align="left">

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
| **DevOps and Automation** | Automated infrastructure deployment and service configuration |
| **Infrastructure as Code** | Provisioning networks, storage volumes, virtual machines & cloud-init with Terraform |
| **Configuration Management** | Configuring servers and services with Ansible |
| **Linux Administration** | Managing Ubuntu and Alpine Linux systems, users, permissions, packages, and services |
| **Virtualization** | Working with KVM, QEMU, and libvirt |
| **Network Engineering** | Network segmentation, routing, NAT, VPN, DNS, and firewall configuration |
| **High Availability** | Load balancing, replication, health checks, and automatic service failover |
| **Database Administration** | PostgreSQL, Patroni, etcd, streaming replication, and automatic primary promotion |
| **Distributed Storage** | S3-compatible Garage storage and software RAID 1 |
| **Containerization** | Deploying web services and infrastructure components with Docker |
| **Monitoring and Observability** | Collecting metrics and logs with Prometheus, Grafana, and Loki + Alerts via Telegram Bot |
| **Backup and Recovery** | Automated backups using Restic |
| **Cybersecurity** | SSH key authentication, VPN access, firewalls, TLS, PKI, and access control |
| **Scripting** | Bash, Python and HTML scripting |
| **Troubleshooting** | Diagnosing networking, SSH, cloud-init, libvirt, and cluster-related issues |
| **Version Control and Documentation** | Managing source code with Git and documenting the infrastructure architecture |
