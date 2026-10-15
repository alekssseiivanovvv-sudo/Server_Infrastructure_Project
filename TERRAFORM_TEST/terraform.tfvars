images_dir   = "/var/lib/libvirt/images"
storage_pool = "default"

vm-routers = {
  cloud-router = {
    host              = "host_1"
    name              = "cloud-router"
    vcpus             = 1
    ram               = 512
    system_drive_size = 5
    #files added by ansible
    base_image = "alpine"
    cloud_init = "${alpine_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    wan_network = "default"
    wan_mac     = "52:54:00:74:01:01"
    lan_network = "cloud-lan"
    lan_mac     = "52:54:00:74:01:02"
    autostart   = true
  }

  east-router = {
    host              = "host_1"
    name              = "east-router"
    vcpus             = 1
    ram               = 512
    system_drive_size = 5
    #files added by ansible
    base_image = "alpine"
    cloud_init = "${alpine_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    wan_network = "default"
    wan_mac     = "52:54:00:72:01:01"
    lan_network = "east-lan"
    lan_mac     = "52:54:00:72:01:02"
    autostart   = true
  }

  west-router = {
    host              = "host_2"
    name              = "west-router"
    vcpus             = 1
    ram               = 512
    system_drive_size = 5
    #files added by ansible
    base_image = "alpine"
    cloud_init = "${alpine_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    wan_network = "default"
    wan_mac     = "52:54:00:73:01:01"
    lan_network = "west-lan"
    lan_mac     = "52:54:00:73:01:02"
    autostart   = true
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
    cloud_init = "${ubuntu_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "east-lan"
    lan_mac     = "52:54:00:72:02:01"
    autostart   = true
  }
  west-db = {
    host              = "host_2"
    name              = "west-db"
    vcpus             = 2
    ram               = 3072
    system_drive_size = 20
    #files added by ansible
    base_image = "ubuntu"
    cloud_init = "${ubuntu_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "west-lan"
    lan_mac     = "52:54:00:73:02:01"
    autostart   = true
  }
  cloud-quorum = {
    host              = "host_1"
    name              = "cloud-quorum"
    vcpus             = 1
    ram               = 2048
    system_drive_size = 20
    #files added by ansible
    base_image = "ubuntu"
    cloud_init = "${ubuntu_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "cloud-lan"
    lan_mac     = "52:54:00:74:02:01"
    autostart   = true
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
    cloud_init = "${ubuntu_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "east-lan"
    lan_mac     = "52:54:00:72:03:01"
    autostart   = true
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
    cloud_init = "${ubuntu_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "west-lan"
    lan_mac     = "52:54:00:73:03:01"
    autostart   = true
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
    cloud_init = "${ubuntu_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "cloud-lan"
    lan_mac     = "52:54:00:74:03:01"
    autostart   = true
  }

  east-web = {
    host              = "host_1"
    name              = "east-web"
    vcpus             = 2
    ram               = 3072
    system_drive_size = 20
    #files added by ansible
    base_image = "alpine"
    cloud_init = "${alpine_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "east-lan"
    lan_mac     = "52:54:00:72:04:01"
    autostart   = true
  }

  west-web = {
    host              = "host_2"
    name              = "west-web"
    vcpus             = 2
    ram               = 3072
    system_drive_size = 20
    #files added by ansible
    base_image = "alpine"
    cloud_init = "${alpine_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "west-lan"
    lan_mac     = "52:54:00:73:04:01"
    autostart   = true
  }

  cloud-load-balancer = {
    host              = "host_1"
    name              = "cloud-load-balancer"
    vcpus             = 1
    ram               = 2048
    system_drive_size = 20
    #files added by ansible
    base_image = "alpine"
    cloud_init = "${alpine_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "cloud-lan"
    lan_mac     = "52:54:00:74:04:01"
    autostart   = true
  }

  cloud-monitoring = {
    host              = "host_1"
    name              = "cloud-monitoring"
    vcpus             = 1
    ram               = 2048
    system_drive_size = 30
    #files added by ansible
    base_image = "ubuntu"
    cloud_init = "${ubuntu_cloud_init}" ## еще раз проверить путь после доработки Ansible
    #network configuration
    lan_network = "cloud-lan"
    lan_mac     = "52:54:00:74:05:01"
    autostart   = true
  }
}