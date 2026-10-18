module "routers_host_1" {
  source   = "./modules/vm"
  for_each = local.routers_host_1

  providers = {
    libvirt = libvirt.host_1
  }

  name                = each.value.name
  vcpus               = each.value.vcpus
  ram                 = each.value.ram
  system_drive_size   = each.value.system_drive_size
  base_image_path     = local.base_images[each.value.base_image]
  images_dir          = var.images_dir
  storage_pool_prefix = var.storage_pool
  autostart           = each.value.autostart
  console             = each.value.console
  console_type        = each.value.console_type
  console_target_type = each.value.console_target_type
  console_port        = each.value.console_port

  cloud_init_user_data = templatefile("${path.module}/cloud-init/router-alpine-user-data.yaml.tftpl", {
    hostname           = replace(each.value.name, "_", "-")
    ssh_public_key     = local.ansible_admin_public_key
    ssh_port           = var.ssh_port
    swap_size_mb       = each.value.swap_size_mb
    lan_subnet         = each.value.lan_subnet
    tailscale_auth_key = var.router_tailscale_auth_keys[each.key]
  })

  cloud_init_meta_data = templatefile("${path.module}/cloud-init/meta-data.yaml.tftpl", {
    instance_id = "${each.value.name}-001"
    hostname    = replace(each.value.name, "_", "-")
  })

  cloud_init_network_config = templatefile("${path.module}/cloud-init/router-network-config.yaml.tftpl", {
    wan_mac_address = each.value.networks.wan.mac
    lan_mac_address = each.value.networks.lan.mac
    lan_address     = each.value.lan_address
    lan_netmask     = each.value.lan_netmask
  })

  interfaces = [
    {
      network = each.value.networks.wan.bridge
      mac     = each.value.networks.wan.mac
    },
    {
      network = each.value.networks.lan.bridge
      mac     = each.value.networks.lan.mac
    }
  ]
  depends_on = [libvirt_network.cloud_lan, libvirt_network.east_lan]
}
module "routers_host_2" {
  source   = "./modules/vm"
  for_each = local.routers_host_2

  providers = {
    libvirt = libvirt.host_2
  }

  name                = each.value.name
  vcpus               = each.value.vcpus
  ram                 = each.value.ram
  system_drive_size   = each.value.system_drive_size
  base_image_path     = local.base_images[each.value.base_image]
  images_dir          = var.images_dir
  storage_pool_prefix = var.storage_pool
  autostart           = each.value.autostart
  console             = each.value.console
  console_type        = each.value.console_type
  console_target_type = each.value.console_target_type
  console_port        = each.value.console_port

  cloud_init_user_data = templatefile("${path.module}/cloud-init/router-alpine-user-data.yaml.tftpl", {
    hostname           = replace(each.value.name, "_", "-")
    ssh_public_key     = local.ansible_admin_public_key
    ssh_port           = var.ssh_port
    swap_size_mb       = each.value.swap_size_mb
    lan_subnet         = each.value.lan_subnet
    tailscale_auth_key = var.router_tailscale_auth_keys[each.key]
  })

  cloud_init_meta_data = templatefile("${path.module}/cloud-init/meta-data.yaml.tftpl", {
    instance_id = "${each.value.name}-001"
    hostname    = replace(each.value.name, "_", "-")
  })

  cloud_init_network_config = templatefile("${path.module}/cloud-init/router-network-config.yaml.tftpl", {
    wan_mac_address = each.value.networks.wan.mac
    lan_mac_address = each.value.networks.lan.mac
    lan_address     = each.value.lan_address
    lan_netmask     = each.value.lan_netmask
  })

  interfaces = [
    {
      network = each.value.networks.wan.bridge
      mac     = each.value.networks.wan.mac
    },
    {
      network = each.value.networks.lan.bridge
      mac     = each.value.networks.lan.mac
    }
  ]
  depends_on = [libvirt_network.west_lan]
}
