# isolated networks. current format is for newer versions of libvirt provider. For older versions, see the commented-out code below.

#host 1
resource "libvirt_network" "east_lan" {
  provider  = libvirt.host_1
  name      = "east-lan"
  autostart = true

  bridge = {
    name  = "virbr-east"
    stp   = "on"
    delay = "0"
  }
}

resource "libvirt_network" "cloud_lan" {
  provider  = libvirt.host_1
  name      = "cloud-lan"
  autostart = true

  bridge = {
    name  = "virbr-cloud"
    stp   = "on"
    delay = "0"
  }
}
