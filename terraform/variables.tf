#variables.tf

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
  default     = "/var/lib/libvirt/images/templates/ubuntu-26.04-server-cloudimg-amd64.img"
}

variable "alpine_image" {
  description = "Alpine cloud-image template."
  type        = string
  default     = "/var/lib/libvirt/images/templates/alpine-3.24.2-x86_64-cloudinit-r0.qcow2"
}

variable "storage_pool" {
  description = "Libvirt storage pool for VM disks."
  type        = string
  default     = "default"
}

variable "vm-routers" {
  description = "A map of virtual routers to create."
  type = map(object({
    host              = string           # The host to create the router on (host_1 or host_2)
    name              = string           # The name of the router
    vcpus             = number           # The number of virtual CPUs to allocate to the router
    ram               = number           # The amount of memory (in MB) to allocate to the router
    system_drive_size = number           # The size of the drive (in GB) to allocate to the router
    base_image        = string           # The image to use for the router
    lan_address       = optional(string) # Static LAN address without a prefix
    lan_subnet        = optional(string) # Advertised LAN subnet, for example 192.168.72.0/27
    lan_netmask       = optional(string, "255.255.255.224")
    swap_size_mb      = optional(number, 512)
    networks = object({
      wan = object({ bridge = string, mac = string })
      lan = optional(object({ bridge = string, mac = string }))
    })
    autostart           = optional(bool, true)       # Whether to automatically start the router on host boot (default: true)
    console             = optional(bool, true)       # Whether to enable console access to the router (default: false)
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
      name   = string # The name of the extra drive
      size   = number # The size of each extra drive (in GB)
      serial = string # Stable guest-visible serial, for example data1
    })), [])
    base_image             = string # The image to use for the VM
    ip_address             = string # Static LAN address without a prefix
    gateway                = string # Site router LAN address
    netmask                = optional(string, "255.255.255.224")
    swap_size_mb           = optional(number, 2048)
    configure_storage_raid = optional(bool, false)
    networks = object({
      wan = optional(object({ bridge = string, mac = string })) # In this project by wan it means default KVM switch which allows machine directly to the internet without using virtual router
      lan = object({ bridge = string, mac = string })
    })
    autostart           = optional(bool, true)       # Whether to automatically start the VM on host boot (default: true)
    console             = optional(bool, true)       # Whether to enable console access to the router (default: false)
    console_type        = optional(string, "serial") # The type of console to use (default: serial)
    console_target_type = optional(string, "pty")    # The target type for the console (default: pty)
    console_port        = optional(number, 0)        # The port to use for console access (default: 0, which means no console access)
  }))
}

variable "ansible_admin_public_key_file" {
  description = "Public SSH key installed for ansible_admin by cloud-init."
  type        = string
  default     = "~/.ssh/ansible.pub"
}

variable "ssh_port" {
  description = "SSH port configured by cloud-init on all guest VMs."
  type        = number
  default     = 2222

  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535
    error_message = "ssh_port must be between 1 and 65535."
  }
}

variable "router_tailscale_auth_keys" {
  description = "Per-router Tailscale auth keys. Supply through secrets.auto.tfvars or TF_VAR_router_tailscale_auth_keys."
  type        = map(string)
  sensitive   = true

  validation {
    condition = alltrue([
      for router_name in ["cloud_router", "east_router", "west_router"] :
      try(trimspace(var.router_tailscale_auth_keys[router_name]) != "", false)
    ])
    error_message = "Provide non-empty auth keys for cloud_router, east_router and west_router."
  }
}

variable "enabled_hosts" {
  description = "Hypervisors on which resources should be created."
  type        = set(string)
  default     = ["host_1", "host_2"]

  validation {
    condition = alltrue([
      for host in var.enabled_hosts :
      contains(["host_1", "host_2"], host)
    ])

    error_message = "Allowed hosts: host_1 and host_2."
  }
}
