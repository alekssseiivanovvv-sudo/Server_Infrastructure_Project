# isolated networks. current format is for newer versions of libvirt provider.

#host 1
resource "libvirt_network" "east_lan" {
  count    = contains(var.enabled_hosts, "host_1") ? 1 : 0 #added for test only on 1 host
  provider = libvirt.host_1

  name      = "east-lan"
  autostart = true

  bridge = {
    name  = "virbr-east"
    stp   = "on"
    delay = "0"
  }
}

resource "libvirt_network" "cloud_lan" {
  count    = contains(var.enabled_hosts, "host_1") ? 1 : 0
  provider = libvirt.host_1

  name      = "cloud-lan"
  autostart = true

  bridge = {
    name  = "virbr-cloud"
    stp   = "on"
    delay = "0"
  }
}

resource "libvirt_network" "west_lan" {
  count    = contains(var.enabled_hosts, "host_2") ? 1 : 0 #added for test only on 1 host
  provider = libvirt.host_2

  name      = "west-lan"
  autostart = true

  bridge = {
    name  = "virbr-west"
    stp   = "on"
    delay = "0"
  }
}