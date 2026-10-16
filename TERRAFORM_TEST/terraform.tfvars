images_dir   = "/var/lib/libvirt/images"
storage_pool = "default"

#routers must be created before servers, because servers depend on routers for network connectivity.
vm-routers = {
  cloud_router = {
    host              = "host_1"
    name              = "cloud_router"
    vcpus             = 1
    ram               = 512
    system_drive_size = 5

    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/vms/cloud_router/seed.iso"

    wan_bridge = "default"
    wan_mac    = "52:54:00:74:01:01"
    lan_bridge = "cloud-lan"
    lan_mac    = "52:54:00:74:01:02"

    autostart = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }

  east_router = {
    host              = "host_1"
    name              = "east_router"
    vcpus             = 1
    ram               = 512
    system_drive_size = 5
    #files added by ansible
    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/vms/east_router/seed.iso"
    #network configuration
    wan_bridge = "default"
    wan_mac    = "52:54:00:72:01:01"
    lan_bridge = "east-lan"
    lan_mac    = "52:54:00:72:01:02"

    autostart = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }

  west_router = {
    host              = "host_2"
    name              = "west_router"
    vcpus             = 1
    ram               = 512
    system_drive_size = 5
    #files added by ansible
    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/vms/west_router/seed.iso"
    #network configuration
    wan_bridge = "default"
    wan_mac    = "52:54:00:73:01:01"
    lan_bridge = "west-lan"
    lan_mac    = "52:54:00:73:01:02"

    autostart = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }
}

#___________________________________________________________________________________________________________

vm-servers = {
  east-db = {
    host              = "host_1"
    name              = "east-db"
    vcpus             = 2
    ram               = 3072
    system_drive_size = 20
    #files added by ansible
    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/<имя-VM>-seed.iso" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "east-lan"
    lan_mac     = "52:54:00:72:02:01"
    autostart   = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }
  west-db = {
    host              = "host_2"
    name              = "west-db"
    vcpus             = 2
    ram               = 3072
    system_drive_size = 20
    #files added by ansible
    base_image = "ubuntu"
    cloud_init = "$/var/lib/libvirt/images/<имя-VM>-seed.iso" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "west-lan"
    lan_mac     = "52:54:00:73:02:01"
    autostart   = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }
  cloud-quorum = {
    host              = "host_1"
    name              = "cloud-quorum"
    vcpus             = 1
    ram               = 2048
    system_drive_size = 20
    #files added by ansible
    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/<имя-VM>-seed.iso" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "cloud-lan"
    lan_mac     = "52:54:00:74:02:01"
    autostart   = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }

  east-storage = {
    host              = "host_1"
    name              = "east-storage"
    vcpus             = 1
    ram               = 3072
    system_drive_size = 20
    extra_drives = [
      {
        name     = "east-storage-raid-1"
        quantity = 1
        size     = 15
      },
      {
        name     = "east-storage-raid-2"
        quantity = 1
        size     = 15
      }
    ]
    #files added by ansible
    base_image = "ubuntu"
    cloud_init = "$/var/lib/libvirt/images/<имя-VM>-seed.iso" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "east-lan"
    lan_mac     = "52:54:00:72:03:01"
    autostart   = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }

  west-storage = {
    host              = "host_2"
    name              = "west-storage"
    vcpus             = 1
    ram               = 3072
    system_drive_size = 20
    extra_drives = [
      {
        name     = "west-storage-backup-1"
        quantity = 1
        size     = 15
      },
      {
        name     = "west-storage-raid-1"
        quantity = 1
        size     = 15
      }
    ]
    #files added by ansible
    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/<имя-VM>-seed.iso" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "west-lan"
    lan_mac     = "52:54:00:73:03:01"
    autostart   = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }

  s3-storage = {
    host              = "host_1"
    name              = "s3-storage"
    vcpus             = 1
    ram               = 2048
    system_drive_size = 20
    extra_drives = [
      {
        name     = "s3-storage-raid-1"
        quantity = 1
        size     = 15
      },
      {
        name     = "s3-storage-raid-2"
        quantity = 1
        size     = 15
      }
    ]
    #files added by ansible
    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/<имя-VM>-seed.iso" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "cloud-lan"
    lan_mac     = "52:54:00:74:03:01"
    autostart   = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }

  east-web = {
    host              = "host_1"
    name              = "east-web"
    vcpus             = 2
    ram               = 3072
    system_drive_size = 20
    #files added by ansible
    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/<имя-VM>-seed.iso" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "east-lan"
    lan_mac     = "52:54:00:72:04:01"
    autostart   = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }

  west-web = {
    host              = "host_2"
    name              = "west-web"
    vcpus             = 2
    ram               = 3072
    system_drive_size = 20
    #files added by ansible
    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/<имя-VM>-seed.iso" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "west-lan"
    lan_mac     = "52:54:00:73:04:01"
    autostart   = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }

  cloud-load-balancer = {
    host              = "host_1"
    name              = "cloud-load-balancer"
    vcpus             = 1
    ram               = 2048
    system_drive_size = 20
    #files added by ansible
    base_image = "alpine"
    cloud_init = "/var/lib/libvirt/images/<имя-VM>-seed.iso" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "cloud-lan"
    lan_mac     = "52:54:00:74:04:01"
    autostart   = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }

  cloud-monitoring = {
    host              = "host_1"
    name              = "cloud-monitoring"
    vcpus             = 1
    ram               = 2048
    system_drive_size = 30
    #files added by ansible
    base_image = "ubuntu"
    cloud_init = "/var/lib/libvirt/images/<имя-VM>-seed.iso" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "cloud-lan"
    lan_mac     = "52:54:00:74:05:01"
    autostart   = true
    console = true
    console_type = "serial"
    console_target_type = "pty"
    console_port = 1
  }
}