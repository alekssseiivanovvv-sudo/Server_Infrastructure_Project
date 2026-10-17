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

interfaces = [
  {
    network = each.value.networks.lan.bridge
    mac     = each.value.networks.lan.mac
  }
]
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

  interfaces = [
  {
    network = each.value.networks.lan.bridge
    mac     = each.value.networks.lan.mac
  }
]
}