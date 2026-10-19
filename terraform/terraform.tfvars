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

    base_image  = "alpine"
    lan_address = "192.168.74.1"
    lan_subnet  = "192.168.74.0/27"

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

    base_image  = "alpine"
    lan_address = "192.168.72.1"
    lan_subnet  = "192.168.72.0/27"

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

    base_image  = "alpine"
    lan_address = "192.168.73.1"
    lan_subnet  = "192.168.73.0/27"

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
    ip_address = "192.168.72.4"
    gateway    = "192.168.72.1"

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
    ip_address = "192.168.73.4"
    gateway    = "192.168.73.1"

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
    ip_address = "192.168.74.5"
    gateway    = "192.168.74.1"

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
        name   = "east-storage-raid-1"
        size   = 15
        serial = "data1"
      },
      {
        name   = "east-storage-raid-2"
        size   = 15
        serial = "data2"
      }
    ]

    base_image             = "ubuntu"
    ip_address             = "192.168.72.5"
    gateway                = "192.168.72.1"
    configure_storage_raid = true

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
        name   = "west-storage-raid-1"
        size   = 15
        serial = "data1"
      },
      {
        name   = "west-storage-raid-2"
        size   = 15
        serial = "data2"
      }
    ]

    base_image             = "ubuntu"
    ip_address             = "192.168.73.5"
    gateway                = "192.168.73.1"
    configure_storage_raid = true

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
        name   = "cloud-s3-raid-1"
        size   = 15
        serial = "data1"
      },
      {
        name   = "cloud-s3-raid-2"
        size   = 15
        serial = "data2"
      }
    ]

    base_image             = "ubuntu"
    ip_address             = "192.168.74.6"
    gateway                = "192.168.74.1"
    configure_storage_raid = true

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
    ip_address = "192.168.72.3"
    gateway    = "192.168.72.1"

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
    ip_address = "192.168.73.3"
    gateway    = "192.168.73.1"

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
    ip_address = "192.168.72.2"
    gateway    = "192.168.72.1"

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
    ip_address = "192.168.73.2"
    gateway    = "192.168.73.1"

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
    host              = "host_1"
    name              = "cloud-monitoring"
    vcpus             = 1
    ram               = 6144
    system_drive_size = 30

    base_image = "ubuntu"
    ip_address = "192.168.74.3"
    gateway    = "192.168.74.1"

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

vm-external = {
  inet_dns = {
    host              = "host_1"
    name              = "inet-dns"
    vcpus             = 1
    ram               = 512
    system_drive_size = 5
    base_image        = "alpine"
    swap_size_mb      = 512

    network = {
      bridge = "default"
      mac    = "52:54:00:70:01:01"
    }

    autostart = true
  }
}
