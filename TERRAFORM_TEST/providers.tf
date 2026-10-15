terraform {
    required_version = ">= 1.6"
    required_providers {
        libvirt = {
            source  = "dmacvicar/libvirt"
            version = "~> 0.8"
        }
    }
}

provider "libvirt" {
  alias = "host_1"
  uri   = "qemu+sshcmd://host_1/system"
}

provider "libvirt" {
  alias = "host_2"
  uri   = "qemu+sshcmd://host_2/system"
}
