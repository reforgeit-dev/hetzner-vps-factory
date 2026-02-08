variable "hcloud_token" {
  type        = string
  sensitive   = true
  description = "Hetzner Cloud API token (from HCLOUD_TOKEN env var)"
}

variable "server_name" {
  type        = string
  default     = "my-server"
  description = "Hostname for the VPS"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.server_name))
    error_message = "Server name must be lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "server_type" {
  type        = string
  default     = "cx33"
  description = "Hetzner Cloud server type (cx23 = 2vCPU, 4GB RAM, 40GB SSD)"

  validation {
    condition     = can(regex("^(cx|cpx|cax|ccx)[0-9]+$", var.server_type))
    error_message = "Server type must be a valid Hetzner type (cx*, cpx*, cax*, ccx*)."
  }
}

variable "location" {
  type        = string
  default     = "hel1"
  description = "Hetzner Cloud location (nbg1 = Nuremberg)"

  validation {
    condition     = contains(["nbg1", "fsn1", "hel1", "ash", "hil"], var.location)
    error_message = "Location must be one of: nbg1, fsn1, hel1, ash, hil."
  }
}

variable "os_image" {
  type        = string
  default     = "ubuntu-24.04"
  description = "Operating system image"
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
  description = "Path to SSH public key for Ansible provisioning"
}

variable "tailscale_auth_key" {
  type        = string
  sensitive   = true
  description = "Tailscale auth key for auto-provisioning (from TAILSCALE_AUTH_KEY env var)"
}

variable "backups_enabled" {
  type        = bool
  default     = true
  description = "Enable automatic daily backups (keeps last 7, +20% server cost)"
}

variable "storagebox_enabled" {
  type        = bool
  default     = true
  description = "Whether to provision a Hetzner Storage Box"
}

variable "storagebox_type" {
  type        = string
  default     = "bx11"
  description = "Hetzner Storage Box type (bx11 = 1TB, bx21 = 5TB, bx31 = 10TB)"

  validation {
    condition     = can(regex("^bx[0-9]+$", var.storagebox_type))
    error_message = "Storage Box type must be a valid Hetzner type (bx11, bx21, bx31, etc.)."
  }
}
