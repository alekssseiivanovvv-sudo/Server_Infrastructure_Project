resource "libvirt_cloudinit_disk" "init" {
  name           = "${var.name}-cloudinit"
  user_data      = var.cloud_init_user_data
  meta_data      = var.cloud_init_meta_data
  network_config = var.cloud_init_network_config
}

resource "libvirt_volume" "cloudinit" {
  name = "${var.name}-cloudinit.iso"
  pool = libvirt_pool.vm.name

  create = {
    content = {
      url = libvirt_cloudinit_disk.init.path
    }
  }
}
