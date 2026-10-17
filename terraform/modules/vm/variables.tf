variable "name" {
  type = string
}

variable "vcpus" {
  type = number
}

variable "ram" {
  type = number
}

variable "system_drive_size" {
  type = number
}

variable "base_image_path" {
  description = "Existing immutable base image on the KVM host."
  type        = string
}

variable "images_dir" {
  type = string
}

variable "storage_pool_prefix" {
  type = string
}

variable "extra_drives" {
  type = list(object({
    name = string
    size = number
  }))

  default = []
}

variable "interfaces" {
  type = list(object({
    network = string
    mac     = string
  }))
}

variable "autostart" {
  type    = bool
  default = true
}

variable "console" {
  type    = bool
  default = true
}

variable "console_type" {
  type    = string
  default = "serial"
}

variable "console_target_type" {
  type    = string
  default = "pty"
}

variable "console_port" {
  type    = number
  default = 0
}