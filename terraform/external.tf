variable "vm-external" {
  description = "External standalone VMs connected directly to the libvirt default network."

  type = map(object({
    host              = string
    name              = string
    vcpus             = number
    ram               = number
    system_drive_size = number
    base_image        = string
    swap_size_mb      = optional(number, 512)

    network = object({
      bridge = string
      mac    = string
    })

    autostart           = optional(bool, true)
    console             = optional(bool, true)
    console_type        = optional(string, "serial")
    console_target_type = optional(string, "pty")
    console_port        = optional(number, 0)
  }))

  default = {}

  validation {
    condition = alltrue([
      for machine in values(var.vm-external) :
      contains(["host_1", "host_2"], machine.host)
    ])

    error_message = "External VM host must be host_1 or host_2."
  }
}

locals {
  external_host_1 = {
    for key, machine in var.vm-external : key => machine
    if machine.host == "host_1" && contains(var.enabled_hosts, "host_1")
  }

  external_host_2 = {
    for key, machine in var.vm-external : key => machine
    if machine.host == "host_2" && contains(var.enabled_hosts, "host_2")
  }
}

module "external_host_1" {
  source   = "./modules/vm"
  for_each = local.external_host_1

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
  extra_drives        = []

  autostart           = each.value.autostart
  console             = each.value.console
  console_type        = each.value.console_type
  console_target_type = each.value.console_target_type
  console_port        = each.value.console_port

  cloud_init_user_data = templatefile(
    "${path.module}/cloud-init/external-alpine-user-data.yaml.tftpl",
    {
      hostname           = replace(each.value.name, "_", "-")
      ssh_public_key     = local.ansible_admin_public_key
      ssh_port           = var.ssh_port
      swap_size_mb       = each.value.swap_size_mb
      tailscale_auth_key = var.external_tailscale_auth_keys[each.key]
    }
  )

  cloud_init_meta_data = templatefile(
    "${path.module}/cloud-init/meta-data.yaml.tftpl",
    {
      instance_id = "${each.value.name}-001"
      hostname    = replace(each.value.name, "_", "-")
    }
  )

  cloud_init_network_config = templatefile(
    "${path.module}/cloud-init/external-network-config.yaml.tftpl",
    {
      mac_address = each.value.network.mac
    }
  )

  interfaces = [
    {
      network = each.value.network.bridge
      mac     = each.value.network.mac
    }
  ]
}

module "external_host_2" {
  source   = "./modules/vm"
  for_each = local.external_host_2

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
  extra_drives        = []

  autostart           = each.value.autostart
  console             = each.value.console
  console_type        = each.value.console_type
  console_target_type = each.value.console_target_type
  console_port        = each.value.console_port

  cloud_init_user_data = templatefile(
    "${path.module}/cloud-init/external-alpine-user-data.yaml.tftpl",
    {
      hostname           = replace(each.value.name, "_", "-")
      ssh_public_key     = local.ansible_admin_public_key
      ssh_port           = var.ssh_port
      swap_size_mb       = each.value.swap_size_mb
      tailscale_auth_key = var.external_tailscale_auth_keys[each.key]
    }
  )

  cloud_init_meta_data = templatefile(
    "${path.module}/cloud-init/meta-data.yaml.tftpl",
    {
      instance_id = "${each.value.name}-001"
      hostname    = replace(each.value.name, "_", "-")
    }
  )

  cloud_init_network_config = templatefile(
    "${path.module}/cloud-init/external-network-config.yaml.tftpl",
    {
      mac_address = each.value.network.mac
    }
  )

  interfaces = [
    {
      network = each.value.network.bridge
      mac     = each.value.network.mac
    }
  ]
}