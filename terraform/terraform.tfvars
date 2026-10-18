#tfvars

images_dir   = "/var/lib/libvirt/images"
storage_pool = "default"

# Routers must be created before servers because servers depend on their LAN networks.
vm-routers = {
  cloud_router = {
    host              = "host_1"
    name              = "cloud_router"
    vcpus             = 1
    ram               = 512
    system_drive_size = 5

    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/vms/cloud_router/seed.iso"

    networks = {
      wan = {
        bridge = "default"
        mac    = "52:54:00:74:01:01"
      }

      lan = {
        bridge = "cloud-lan"
        mac    = "52:54:00:74:01:02"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  east_router = {
    host              = "host_1"
    name              = "east_router"
    vcpus             = 1
    ram               = 512
    system_drive_size = 5

    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/vms/east_router/seed.iso"

    networks = {
      wan = {
        bridge = "default"
        mac    = "52:54:00:72:01:01"
      }

      lan = {
        bridge = "east-lan"
        mac    = "52:54:00:72:01:02"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  west_router = {
    host              = "host_2"
    name              = "west_router"
    vcpus             = 1
    ram               = 512
    system_drive_size = 5

    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/vms/west_router/seed.iso"

    networks = {
      wan = {
        bridge = "default"
        mac    = "52:54:00:73:01:01"
      }

      lan = {
        bridge = "west-lan"
        mac    = "52:54:00:73:01:02"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }
}

vm-servers = {
  east-db = {
    host              = "host_1"
    name              = "east-db"
    vcpus             = 2
    ram               = 3072
    system_drive_size = 20

    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/vms/east-db/seed.iso"

    networks = {
      lan = {
        bridge = "east-lan"
        mac    = "52:54:00:72:02:01"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  west-db = {
    host              = "host_2"
    name              = "west-db"
    vcpus             = 2
    ram               = 3072
    system_drive_size = 20

    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/vms/west-db/seed.iso"

    networks = {
      lan = {
        bridge = "west-lan"
        mac    = "52:54:00:73:02:01"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  cloud-quorum = {
    host              = "host_1"
    name              = "cloud-quorum"
    vcpus             = 1
    ram               = 2048
    system_drive_size = 20

    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/vms/cloud-quorum/seed.iso"

    networks = {
      lan = {
        bridge = "cloud-lan"
        mac    = "52:54:00:74:02:01"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  east-storage = {
    host              = "host_1"
    name              = "east-storage"
    vcpus             = 1
    ram               = 3072
    system_drive_size = 20

    extra_drives = [
      {
        name = "east-storage-raid-1"
        size = 15
      },
      {
        name = "east-storage-raid-2"
        size = 15
      }
    ]

    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/vms/east-storage/seed.iso"

    networks = {
      lan = {
        bridge = "east-lan"
        mac    = "52:54:00:72:03:01"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  west-storage = {
    host              = "host_2"
    name              = "west-storage"
    vcpus             = 1
    ram               = 3072
    system_drive_size = 20

    extra_drives = [
      {
        name = "west-storage-raid-1"
        size = 15
      },
      {
        name = "west-storage-raid-2"
        size = 15
      }
    ]

    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/vms/west-storage/seed.iso"

    networks = {
      lan = {
        bridge = "west-lan"
        mac    = "52:54:00:73:03:01"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  cloud-s3 = {
    host              = "host_1"
    name              = "cloud-s3"
    vcpus             = 1
    ram               = 2048
    system_drive_size = 20

    extra_drives = [
      {
        name = "cloud-s3-raid-1"
        size = 15
      },
      {
        name = "cloud-s3-raid-2"
        size = 15
      }
    ]

    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/vms/cloud-s3/seed.iso"

    networks = {
      lan = {
        bridge = "cloud-lan"
        mac    = "52:54:00:74:03:01"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  east-web = {
    host              = "host_1"
    name              = "east-web"
    vcpus             = 2
    ram               = 3072
    system_drive_size = 20

    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/vms/east-web/seed.iso"

    networks = {
      lan = {
        bridge = "east-lan"
        mac    = "52:54:00:72:04:01"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  west-web = {
    host              = "host_2"
    name              = "west-web"
    vcpus             = 2
    ram               = 3072
    system_drive_size = 20

    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/vms/west-web/seed.iso"

    networks = {
      lan = {
        bridge = "west-lan"
        mac    = "52:54:00:73:04:01"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  east-load-balancer = {
    host              = "host_1"
    name              = "east-load-balancer"
    vcpus             = 1
    ram               = 1024
    system_drive_size = 20

    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/vms/east-load-balancer/seed.iso"

    networks = {
      lan = {
        bridge = "east-lan"
        mac    = "52:54:00:72:05:01"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  west-load-balancer = {
    host              = "host_2"
    name              = "west-load-balancer"
    vcpus             = 1
    ram               = 1024
    system_drive_size = 20

    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/vms/west-load-balancer/seed.iso"

    networks = {
      lan = {
        bridge = "west-lan"
        mac    = "52:54:00:73:05:01"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }

  cloud-monitoring = {
    host              = "host_2"
    name              = "cloud-monitoring"
    vcpus             = 1
    ram               = 6144
    system_drive_size = 30

    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/vms/cloud-monitoring/seed.iso"

    networks = {
      lan = {
        bridge = "cloud-lan"
        mac    = "52:54:00:74:05:01"
      }
    }

    autostart           = true
    console             = true
    console_type        = "serial"
    console_target_type = "pty"
    console_port        = 0
  }
}
