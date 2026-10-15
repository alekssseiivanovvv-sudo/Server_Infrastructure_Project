variable "images_dir" {
  description = "The directory where the images are stored."
  type        = string
  default     = "/var/lib/libvirt/images"
}

variable "ubuntu_image" {
  description = "The Ubuntu image to use for the virtual machine."
  type        = string
  default     = "${var.images_dir}/ubuntu-26.04-server-cloudimg-amd64.img"
}

variable "ubuntu_default_cloud_init" {
  description = "The default cloud-init configuration to use for the Ubuntu virtual machine."
  type        = string
  default     = "${var.images_dir}/ubuntu-26.04-server-cloudimg-amd64-cloudinit.iso" #!!!путь надо будет обновить после доработки Ansible!!!
}

variable "apline_default_cloud_init" {
  description = "The default cloud-init configuration to use for the Alpine virtual machine."
  type        = string
  default     = "${var.images_dir}/alpine-3.24.2-x86_64-cloudinit-r0.iso" #!!!путь надо будет обновить после доработки Ansible!!!
}

variable "alpine_image" {
  description = "The Alpine image to use for the virtual machine."
  type        = string
  default     = "${var.images_dir}/alpine-3.24.2-x86_64-cloudinit-r0.qcow2"
}

variable "ansible_public_key" {
  description = "The public key to use for Ansible access."
  type        = string
  default     = "~/.ssh/ansible.pub"
}

variable "ssh_port_host" {
  description = "The SSH port to use for connecting to the virtual machine."
  type        = number
  default     = 22
}

variable "ssh_port_vm" {
  description = "The SSH port to use for connecting to the virtual machine."
  type        = number
  default     = 2222 ## used to be secret variable
}

variable "storage_pool" {
  description = "The name of the storage pool to use for the virtual machine."
  type        = string
  default     = "/var/lib/libvirt/images"
}

variable "vm-routers" {
  description = "A map of virtual routers to create."
  type = map(object({
    host              = string               # The host to create the router on (host_1 or host_2)
    name              = string               # The name of the router
    vcpus             = number               # The number of virtual CPUs to allocate to the router
    ram               = number               # The amount of memory (in MB) to allocate to the router
    system_drive_size = number               # The size of the drive (in GB) to allocate to the router
    image             = string               # The image to use for the router
    cloud_init        = string               # The cloud-init configuration to use for the router
    lan_bridge        = string               # The name of the LAN bridge to connect the router to
    lan_mac           = string               # The MAC address to assign to the router's LAN interface
    wan_bridge        = optional(string)     # The name of the WAN bridge to connect the router to (optional)
    wan_mac           = optional(string)     # The MAC address to assign to the router's WAN interface (optional)
    auto_start        = optional(bool, true) # Whether to automatically start the router on host boot (default: true)
  }))
}

#routers must be created first, as they are used to connect the VMs to the network.

variable "vm-servers" {
  description = "A map of virtual servers to create."
  type = map(object({
    host              = string # The host to create the VM on (host_1 or host_2)
    name              = string # The name of the VM
    vcpus             = number # The number of virtual CPUs to allocate to the VM
    ram               = number # The amount of memory (in MB) to allocate to the VM
    system_drive_size = number # The size of the drive (in GB) to allocate to the VM
    extra_drives = optional(list(object({
      name     = string # The name of the extra drive
      quantity = number # The number of extra drives to create
      size     = number # The size of each extra drive (in GB)
    })))
    image      = string               # The image to use for the VM
    cloud_init = string               # The cloud-init configuration to use for the VM
    lan_bridge = string               # The name of the LAN bridge to connect the VM to
    lan_mac    = string               # The MAC address to assign to the VM's LAN interface
    wan_bridge = optional(string)     # The name of the WAN bridge to connect the VM to (optional
    wan_mac    = optional(string)     # The MAC address to assign to the VM's WAN interface (optional
    auto_start = optional(bool, true) # Whether to automatically start the VM on host boot (default: true)
  }))
}

variable "enabled_hosts" {
  description = "available hosts for VM deployment."
  type        = set(string)
  default     = ["host_1"]   #
}