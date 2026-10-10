locals {
  storage_servers = {
    for name, server in var.servers : name => server
    if server.storage
  }

  ansible_public_key = trimspace(file(pathexpand(var.ansible_public_key_file)))
}

resource "libvirt_pool" "project" {
  name = var.pool_name
  type = "dir"

  target = {
    path = var.pool_path
  }

  create = {
    build     = true
    start     = true
    autostart = true
  }

  destroy = {
    delete = false
  }
}

resource "libvirt_volume" "router_disk" {
  for_each = var.routers

  name     = "${each.key}.qcow2"
  pool     = libvirt_pool.project.name
  capacity = 2 * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = var.alpine_image_path

    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_volume" "server_disk" {
  for_each = var.servers

  name     = "${each.key}.qcow2"
  pool     = libvirt_pool.project.name
  capacity = each.value.disk_gib * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = (
      each.value.os == "alpine"
      ? var.alpine_image_path
      : var.ubuntu_image_path
    )

    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_volume" "data1" {
  for_each = local.storage_servers

  name       = "${each.key}-data1.qcow2"
  pool       = libvirt_pool.project.name
  capacity   = 30 * 1024 * 1024 * 1024
  allocation = 0

  target = {
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_volume" "data2" {
  for_each = local.storage_servers

  name       = "${each.key}-data2.qcow2"
  pool       = libvirt_pool.project.name
  capacity   = 30 * 1024 * 1024 * 1024
  allocation = 0

  target = {
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "router" {
  for_each = var.routers

  name = "${each.key}-cloud-init"

  meta_data = yamlencode({
    instance-id    = "${each.key}-001"
    local-hostname = each.value.hostname
  })

  network_config = templatefile("${path.module}/templates/router-network-config.yaml.tftpl", {
    wan_mac = each.value.wan_mac
    lan_mac = each.value.lan_mac
    lan_ip  = each.value.lan_ip
  })

  user_data = templatefile("${path.module}/templates/router-user-data.yaml.tftpl", {
    hostname            = each.value.hostname
    admin_password_hash = var.admin_password_hash
    ansible_public_key  = local.ansible_public_key
    ssh_port            = var.ssh_port
    tailscale_auth_key  = var.tailscale_auth_key
    lan_subnet          = each.value.lan_subnet
  })
}

resource "libvirt_cloudinit_disk" "server" {
  for_each = var.servers

  name = "${each.key}-cloud-init"

  meta_data = yamlencode({
    instance-id    = "${each.key}-001"
    local-hostname = replace(each.key, "_", "-")
  })

  network_config = templatefile("${path.module}/templates/server-network-config.yaml.tftpl", {
    mac     = each.value.mac
    ip      = each.value.ip
    gateway = each.value.gateway
  })

  user_data = templatefile("${path.module}/templates/${each.value.os}-user-data.yaml.tftpl", {
    hostname            = replace(each.key, "_", "-")
    admin_password_hash = var.admin_password_hash
    ansible_public_key  = local.ansible_public_key
    ssh_port            = var.ssh_port
    storage             = each.value.storage
  })
}

resource "libvirt_volume" "router_cloudinit" {
  for_each = var.routers

  name = "${each.key}-cloud-init.iso"
  pool = libvirt_pool.project.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.router[each.key].path
    }
  }
}

resource "libvirt_volume" "server_cloudinit" {
  for_each = var.servers

  name = "${each.key}-cloud-init.iso"
  pool = libvirt_pool.project.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.server[each.key].path
    }
  }
}

resource "libvirt_domain" "router" {
  for_each = var.routers

  name        = each.key
  memory      = 1024
  memory_unit = "MiB"
  vcpu        = 1
  type        = "kvm"
  running     = true
  autostart   = true

os = {
  type         = "hvm"
  type_arch    = "x86_64"
  type_machine = "q35"
  boot_devices = [
    { dev = "hd" }
  ]
}

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.router_disk[each.key].pool
            volume = libvirt_volume.router_disk[each.key].name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        driver = {
          type = "qcow2"
        }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.router_cloudinit[each.key].pool
            volume = libvirt_volume.router_cloudinit[each.key].name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
        read_only = true
      }
    ]

    interfaces = [
      {
        type = "network"
        mac  = { address = each.value.wan_mac }
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = "default"
          }
        }
      },
      {
        type = "network"
        mac  = { address = each.value.lan_mac }
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = "internal"
          }
        }
      }
    ]
  }
}

resource "libvirt_domain" "server" {
  for_each = var.servers

  name        = each.key
  memory      = each.value.memory
  memory_unit = "MiB"
  vcpu        = each.value.cpus
  type        = "kvm"
  running     = true
  autostart   = true

os = {
  type         = "hvm"
  type_arch    = "x86_64"
  type_machine = "q35"
  boot_devices = [
    { dev = "hd" }
  ]
}

  devices = {
    disks = concat(
      [
        {
          source = {
            volume = {
              pool   = libvirt_volume.server_disk[each.key].pool
              volume = libvirt_volume.server_disk[each.key].name
            }
          }
          target = {
            dev = "vda"
            bus = "virtio"
          }
          driver = {
            type = "qcow2"
          }
        },
        {
          device = "cdrom"
          source = {
            volume = {
              pool   = libvirt_volume.server_cloudinit[each.key].pool
              volume = libvirt_volume.server_cloudinit[each.key].name
            }
          }
          target = {
            dev = "sda"
            bus = "sata"
          }
          read_only = true
        }
      ],
      each.value.storage ? [
        {
          source = {
            volume = {
              pool   = libvirt_volume.data1[each.key].pool
              volume = libvirt_volume.data1[each.key].name
            }
          }
          target = {
            dev = "vdb"
            bus = "virtio"
          }
          driver = {
            type = "qcow2"
          }
          serial = "data1"
        },
        {
          source = {
            volume = {
              pool   = libvirt_volume.data2[each.key].pool
              volume = libvirt_volume.data2[each.key].name
            }
          }
          target = {
            dev = "vdc"
            bus = "virtio"
          }
          driver = {
            type = "qcow2"
          }
          serial = "data2"
        }
      ] : []
    )

    interfaces = [
      {
        type = "network"
        mac  = { address = each.value.mac }
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = "internal"
          }
        }
      }
    ]
  }
}

