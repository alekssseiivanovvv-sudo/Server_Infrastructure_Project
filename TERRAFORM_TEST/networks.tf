## No need to create default network, as it is already created by libvirt. The default network is used for NAT and DHCP, and is not needed for this project.

#isolated networks

# host 1
resource "libvirt_network" "cloud_lan" {
  provider = libvirt.host_1
  name = "cloud-lan"
  mode = "none"
  address = ["192.168.74.0/27"]
  bridge = "virbr-cloud"
  autostart = true
}

resource "libvirt_network" "east_lan" {
  provider = libvirt.host_1
  name = "east-lan"
  mode = "none"
  address = ["192.168.72.0/27"]
  bridge = "virbr-east"
  autostart = true
}

# host 2

resource "libvirt_network" "west_lan" {
  provider = libvirt.host_2
  name = "west-lan"
  mode = "none"
  address = ["192.168.73.0/27"]
  bridge = "virbr-west"
  autostart = true
}