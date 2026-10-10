locals {
 
  ansible_public_key_file = "~/.ssh/ansible.pub"

  host_1_routers = {
    cloud_router = {
      hostname   = "cloud-router"
      lan_ip     = "192.168.74.1"
      lan_subnet = "192.168.74.0/27"
      wan_mac    = "52:54:00:74:01:01"
      lan_mac    = "52:54:00:74:01:02"
    }

    east_router = {
      hostname   = "east-router"
      lan_ip     = "192.168.72.1"
      lan_subnet = "192.168.72.0/27"
      wan_mac    = "52:54:00:72:01:01"
      lan_mac    = "52:54:00:72:01:02"
    }
  }

  host_1_servers = {
    east_web = {
      os       = "alpine"
      ip       = "192.168.72.2"
      gateway  = "192.168.72.1"
      memory   = 3072
      cpus     = 2
      disk_gib = 20
      mac      = "52:54:00:72:02:01"
      storage  = false
    }

    east_db = {
      os       = "ubuntu"
      ip       = "192.168.72.3"
      gateway  = "192.168.72.1"
      memory   = 4096
      cpus     = 2
      disk_gib = 30
      mac      = "52:54:00:72:03:01"
      storage  = false
    }

    east_storage = {
      os       = "ubuntu"
      ip       = "192.168.72.4"
      gateway  = "192.168.72.1"
      memory   = 4096
      cpus     = 2
      disk_gib = 20
      mac      = "52:54:00:72:04:01"
      storage  = true
    }

    load_balancer = {
      os       = "alpine"
      ip       = "192.168.74.4"
      gateway  = "192.168.74.1"
      memory   = 2048
      cpus     = 1
      disk_gib = 10
      mac      = "52:54:00:74:04:01"
      storage  = false
    }

    monitoring = {
      os       = "ubuntu"
      ip       = "192.168.74.3"
      gateway  = "192.168.74.1"
      memory   = 6144
      cpus     = 2
      disk_gib = 40
      mac      = "52:54:00:74:03:01"
      storage  = false
    }
  }

  host_2_routers = {
    west_router = {
      hostname   = "west-router"
      lan_ip     = "192.168.73.1"
      lan_subnet = "192.168.73.0/27"
      wan_mac    = "52:54:00:73:01:01"
      lan_mac    = "52:54:00:73:01:02"
    }
  }

  host_2_servers = {
    west_web = {
      os       = "alpine"
      ip       = "192.168.73.2"
      gateway  = "192.168.73.1"
      memory   = 3072
      cpus     = 2
      disk_gib = 20
      mac      = "52:54:00:73:02:01"
      storage  = false
    }

    west_db = {
      os       = "ubuntu"
      ip       = "192.168.73.3"
      gateway  = "192.168.73.1"
      memory   = 4096
      cpus     = 2
      disk_gib = 30
      mac      = "52:54:00:73:03:01"
      storage  = false
    }

    west_storage = {
      os       = "ubuntu"
      ip       = "192.168.73.4"
      gateway  = "192.168.73.1"
      memory   = 4096
      cpus     = 2
      disk_gib = 20
      mac      = "52:54:00:73:04:01"
      storage  = true
    }
  }
}

module "host_1" {
  source = "./modules/hypervisor"

  providers = {
    libvirt = libvirt.host_1
  }

  pool_name               = "server_infrastructure_host_1"
  pool_path               = "/mnt/p5+/KVM/terraform-host-1"
  routers                 = local.host_1_routers
  servers                 = local.host_1_servers
  ansible_public_key_file = local.ansible_public_key_file
  admin_password_hash     = var.admin_password_hash
  ssh_port                = var.ssh_port
  tailscale_auth_key      = var.tailscale_auth_key
}

module "host_2" {
  source = "./modules/hypervisor"

  providers = {
    libvirt = libvirt.host_2
  }

  pool_name               = "server_infrastructure_host_2"
  pool_path               = "/mnt/disk/VM/terraform-host-2"
  routers                 = local.host_2_routers
  servers                 = local.host_2_servers
  ansible_public_key_file = local.ansible_public_key_file
  admin_password_hash     = var.admin_password_hash
  ssh_port                = var.ssh_port
  tailscale_auth_key      = var.tailscale_auth_key
}

