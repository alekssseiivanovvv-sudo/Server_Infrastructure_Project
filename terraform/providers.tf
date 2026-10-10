provider "libvirt" {
  alias = "host_1"
  uri   = "qemu+sshcmd://ansible_admin@100.64.0.10/system"
}

provider "libvirt" {
  alias = "host_2"
  uri   = "qemu+sshcmd://ansible_admin@100.64.0.11/system"
}

