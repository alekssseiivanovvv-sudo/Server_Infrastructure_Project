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

variable "alpine_image_path" {
  type = string
}

variable "ubuntu_image_path" {
  type = string
}