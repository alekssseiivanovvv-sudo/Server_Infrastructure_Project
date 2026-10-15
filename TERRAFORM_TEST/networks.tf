## No need to create default network, as it is already created by libvirt. The default network is used for NAT and DHCP, and is not needed for this project.

resource "libvirt_network" "cloud_lan" {
  provider = libvirt.host_1
  name = "cloud-lan"
  mode = "nat"
  address = ["192.168.74.0/27"]
  bridge = "br0"
  domain = "lan_1.local"
  autostart = true
}

resource "libvirt_network" "east_lan" {
  provider = libvirt.host_1
  name = "east-lan"
  mode = "nat"
  address = ["192.168.72.0/27"]
  bridge = "br0"
  domain = "lan_2.local"
}

# host 2

resource "libvirt_network" "west_lan" {
  provider = libvirt.host_2
  name = "west-lan"
  mode = "nat"
  address = ["192.168.73.0/27"]
}