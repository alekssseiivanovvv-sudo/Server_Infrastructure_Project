###############################################################################
# Router domains
#
# Ansible prepares the router disk and its cloud-init ISO. Terraform only
# defines and starts the libvirt domains using the values in terraform.tfvars.
###############################################################################

locals {
  # Provider aliases cannot be selected dynamically. The routers are therefore
  # split by hypervisor, while their common device configuration stays here.
  host_1_routers = {
    for key, router in var.vm-routers : key => router
    if router.host == "host_1"
  }

  host_2_routers = {
    for key, router in var.vm-routers : key => router
    if router.host == "host_2"
  }

  router_devices = {
    for key, router in var.vm-routers : key => {
      disks = [
        {
          source = {
            file = {
              file = "${dirname(router.cloud_init)}/${router.name}.qcow2"
            }
          }
          target = {
            dev = "vda"
            bus = "virtio"
          }
          driver = { type = "qcow2" }
        },
        {
          device = "cdrom"
          source = {
            file = { file = router.cloud_init }
          }
          target = {
            dev = "sda"
            bus = "sata"
          }
        }
      ]

      interfaces = [
        {
          type   = "network"
          mac    = { address = router.wan_mac }
          model  = { type = "virtio" }
          source = { network = { network = router.wan_bridge } }
        },
        {
          type   = "network"
          mac    = { address = router.lan_mac }
          model  = { type = "virtio" }
          source = { network = { network = router.lan_bridge } }
        }
      ]

      consoles = router.console ? [
        {
          target = {
            type = router.console_type
            port = router.console_port
          }
        }
      ] : []
    }
  }
}

resource "libvirt_domain" "routers_host_1" {
  provider = libvirt.host_1
  for_each = local.host_1_routers

  name        = each.value.name
  type        = "kvm"
  memory      = each.value.ram
  memory_unit = "MiB"
  vcpu        = each.value.vcpus
  autostart   = each.value.autostart
  running     = true
  os          = { type = "hvm" }
  devices     = local.router_devices[each.key]

  depends_on = [libvirt_network.cloud_lan, libvirt_network.east_lan]
}

resource "libvirt_domain" "routers_host_2" {
  provider = libvirt.host_2
  for_each = local.host_2_routers

  name        = each.value.name
  type        = "kvm"
  memory      = each.value.ram
  memory_unit = "MiB"
  vcpu        = each.value.vcpus
  autostart   = each.value.autostart
  running     = true
  os          = { type = "hvm" }
  devices     = local.router_devices[each.key]

  depends_on = [libvirt_network.west_lan]
}
