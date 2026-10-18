module "servers_host_1" {
  source   = "./modules/vm"
  for_each = local.servers_host_1

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
  extra_drives        = each.value.extra_drives
  autostart           = each.value.autostart
  console             = each.value.console
  console_type        = each.value.console_type
  console_target_type = each.value.console_target_type
  console_port        = each.value.console_port

  interfaces = [
    {
      network = each.value.networks.lan.bridge
      mac     = each.value.networks.lan.mac
    }
  ]

  depends_on = [
    time_sleep.wait_after_routers
  ]
}

module "servers_host_2" {
  source   = "./modules/vm"
  for_each = local.servers_host_2

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
  extra_drives        = each.value.extra_drives
  autostart           = each.value.autostart

  interfaces = [
    {
      network = each.value.networks.lan.bridge
      mac     = each.value.networks.lan.mac
    }
  ]

  depends_on = [
    time_sleep.wait_after_routers
  ]
}