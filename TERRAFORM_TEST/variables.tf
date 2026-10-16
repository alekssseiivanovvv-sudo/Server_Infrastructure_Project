variable "images_dir" {
  description = "Directory for VM disks and cloud-init seed ISOs."
  type        = string
  default     = "/var/lib/libvirt/images"
}

variable "templates_dir" {
  description = "Directory with immutable base cloud images."
  type        = string
  default     = "/var/lib/libvirt/images/templates"
}

variable "ubuntu_image" {
  description = "Ubuntu cloud-image template."
  type        = string
  default     = "/var/lib/libvirt/templates/ubuntu-26.04-server-cloudimg-amd64.img"
}

variable "alpine_image" {
  description = "Alpine cloud-image template."
  type        = string
  default     = "/var/lib/libvirt/templates/alpine-3.24.2-x86_64-cloudinit-r0.qcow2"
}

variable "ubuntu_default_cloud_init" {
  description = "Fallback Ubuntu cloud-init seed ISO."
  type        = string
  default     = "/var/lib/libvirt/ubuntu-default-seed.iso"
}

variable "alpine_default_cloud_init" {
  description = "Fallback Alpine cloud-init seed ISO."
  type        = string
  default     = "/var/lib/libvirt/alpine-default-seed.iso"
}

variable "storage_pool" {
  description = "Libvirt storage pool for VM disks."
  type        = string
  default     = "default"
}

variable "vm-routers" {
  description = "A map of virtual routers to create."
  type = map(object({
    host                = string # The host to create the router on (host_1 or host_2)
    name                = string # The name of the router
    vcpus               = number # The number of virtual CPUs to allocate to the router
    ram                 = number # The amount of memory (in MB) to allocate to the router
    system_drive_size   = number # The size of the drive (in GB) to allocate to the router
    base_image          = string # The image to use for the router
    cloud_init          = string # The cloud-init configuration to use for the router
    wan_bridge          = string # The name of the WAN bridge to connect the router to (optional)
    wan_mac             = string
    lan_bridge          = string                     # The name of the LAN bridge to connect the router to
    lan_mac             = string                     # The MAC address to assign to the router's LAN interface
    autostart           = optional(bool, true)       # Whether to automatically start the router on host boot (default: true)
    console             = optional(bool, false)      # Whether to enable console access to the router (default: false)
    console_type        = optional(string, "serial") # The type of console to use (default: serial)
    console_target_type = optional(string, "pty")    # The target type for the console (default: pty)
    console_port        = optional(number, 0)        # The port to use for console access (default: 0, which means no console access)
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
    base_image          = string                     # The image to use for the VM
    cloud_init          = string                     # The cloud-init configuration to use for the VM
    lan_network         = string                     # The name of the LAN bridge to connect the VM to
    lan_mac             = string                     # The MAC address to assign to the VM's LAN interface
    wan_network         = optional(string)           # The name of the WAN bridge to connect the VM to (optional
    wan_mac             = optional(string)           # The MAC address to assign to the VM's WAN interface (optional
    autostart           = optional(bool, true)       # Whether to automatically start the VM on host boot (default: true)
    console             = optional(bool, false)      # Whether to enable console access to the router (default: false)
    console_type        = optional(string, "serial") # The type of console to use (default: serial)
    console_target_type = optional(string, "pty")    # The target type for the console (default: pty)
    console_port        = optional(number, 0)        # The port to use for console access (default: 0, which means no console access)
  }))
}