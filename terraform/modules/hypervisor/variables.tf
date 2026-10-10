variable "pool_name" {
  type = string
}

variable "pool_path" {
  type = string
}

variable "routers" {
  type = map(object({
    hostname   = string
    lan_ip     = string
    lan_subnet = string
    wan_mac    = string
    lan_mac    = string
  }))
}

variable "servers" {
  type = map(object({
    os       = string
    ip       = string
    gateway  = string
    memory   = number
    cpus     = number
    disk_gib = number
    mac      = string
    storage  = bool
  }))
}

variable "alpine_image_path" {
  description = "Absolute path to the existing Alpine QCOW2 image on this hypervisor"
  type        = string
}

variable "ubuntu_image_path" {
  description = "Absolute path to the existing Ubuntu QCOW2 image on this hypervisor"
  type        = string
}

variable "ansible_public_key_file" {
  type = string
}

variable "admin_password_hash" {
  description = "SHA-512 password hash for ansible_admin"
  type        = string
  sensitive   = true
}

variable "ssh_port" {
  description = "SSH port used by project VMs"
  type        = number
  sensitive   = true

  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535
    error_message = "ssh_port must be between 1 and 65535."
  }
}

variable "tailscale_auth_key" {
  description = "Reusable Tailscale auth key for routers"
  type        = string
  sensitive   = true
}

