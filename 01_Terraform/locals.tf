locals {
  ansible_admin_public_key = trimspace(file(pathexpand(var.ansible_admin_public_key_file)))

  base_images = {
    ubuntu = var.ubuntu_image
    alpine = var.alpine_image
  }

  routers_host_1 = {
    for key, router in var.vm-routers : key => router
    if router.host == "host_1" && contains(var.enabled_hosts, "host_1") && !contains(var.disabled_vms, key)
  }

  routers_host_2 = {
    for key, router in var.vm-routers : key => router
    if router.host == "host_2" && contains(var.enabled_hosts, "host_2") && !contains(var.disabled_vms, key)
  }

  servers_host_1 = {
    for key, server in var.vm-servers : key => server
    if server.host == "host_1" && contains(var.enabled_hosts, "host_1") && !contains(var.disabled_vms, key)
  }

  servers_host_2 = {
    for key, server in var.vm-servers : key => server
    if server.host == "host_2" && contains(var.enabled_hosts, "host_2") && !contains(var.disabled_vms, key)
  }
}
