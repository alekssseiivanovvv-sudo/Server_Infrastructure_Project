provider "libvirt" {
  alias = "host_1"
  uri   = "qemu+sshcmd://host_1/system"
}

provider "libvirt" {
  alias = "host_2"
  uri   = "qemu+sshcmd://host_2/system"
}

