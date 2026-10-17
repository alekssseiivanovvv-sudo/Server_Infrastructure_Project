resource "libvirt_pool" "vm" {
  name = "${var.storage_pool_prefix}-${var.name}"
  type = "dir"

  target = {
    path = "${var.images_dir}/vms/${var.name}"
  }

  create = {
    build     = true
    start     = true
    autostart = true
  }

  destroy = {
    delete = true
  }
}

resource "libvirt_volume" "system" {
  name     = "${var.name}-system.qcow2"
  pool     = libvirt_pool.vm.name
  capacity = var.system_drive_size * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = var.base_image_path

    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_volume" "extra" {
  for_each = {
    for index, disk in var.extra_drives :
    tostring(index) => disk
  }

  name     = "${each.value.name}.qcow2"
  pool     = libvirt_pool.vm.name
  capacity = each.value.size * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }
}