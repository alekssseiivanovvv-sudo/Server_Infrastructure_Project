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
  uri   = "qemu+ssh://ansible_admin@100.64.0.10/system"
}

provider "libvirt" {
  alias = "host_2"
  uri   = "qemu+ssh://ansible_admin@100.64.0.12/system"
}