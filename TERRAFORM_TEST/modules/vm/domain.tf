locals {
  extra_disk_targets = [
    "vdb",
    "vdc",
    "vdd",
    "vde",
    "vdf",
    "vdg",
    "vdh",
    "vdi"
  ]

  system_disk = {
    source = {
      volume = {
        pool   = libvirt_volume.system.pool
        volume = libvirt_volume.system.name
      }
    }

    target = {
      dev = "vda"
      bus = "virtio"
    }

    driver = {
      type = "qcow2"
    }
  }

  extra_disks = [
    for index, disk in var.extra_drives : {
      source = {
        volume = {
          pool   = libvirt_volume.extra[tostring(index)].pool
          volume = libvirt_volume.extra[tostring(index)].name
        }
      }

      target = {
        dev = local.extra_disk_targets[index]
        bus = "virtio"
      }

      driver = {
        type = "qcow2"
      }
    }
  ]

  network_interfaces = [
    for interface in var.interfaces : {
      type = "network"

      model = {
        type = "virtio"
      }

      mac = {
        address = interface.mac
      }

      source = {
        network = {
          network = interface.network
        }
      }
    }
  ]
}

resource "libvirt_domain" "vm" {
  name        = var.name
  type        = "kvm"
  memory      = var.ram
  memory_unit = "MiB"
  vcpu        = var.vcpus

  autostart = var.autostart
  running   = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = ["hd"]
  }

  devices = {
    disks = concat(
      [local.system_disk],
      local.extra_disks
    )

    interfaces = local.network_interfaces
  }
}