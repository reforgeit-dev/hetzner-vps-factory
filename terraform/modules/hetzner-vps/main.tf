terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
    tls = {
      source = "hashicorp/tls"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# =============================================================================
# VPS
# =============================================================================

resource "hcloud_server" "this" {
  name        = var.server_name
  image       = var.os_image
  server_type = var.server_type
  location    = var.location
  ssh_keys    = var.ssh_key_ids
  backups     = var.backups_enabled

  lifecycle {
    ignore_changes = [image]
  }
}

# =============================================================================
# Storage Box (optional)
# =============================================================================

resource "tls_private_key" "storagebox" {
  count     = var.storagebox_enabled ? 1 : 0
  algorithm = "ED25519"
}

resource "random_password" "storagebox" {
  count            = var.storagebox_enabled ? 1 : 0
  length           = 32
  special          = true
  min_upper        = 1
  min_special      = 1
  min_numeric      = 1
  min_lower        = 1
  override_special = "$%/()=?#+-*{}+&"
}

resource "hcloud_storage_box" "this" {
  count            = var.storagebox_enabled ? 1 : 0
  name             = "${var.server_name}-storage"
  storage_box_type = var.storagebox_type
  location         = var.location
  password         = random_password.storagebox[0].result

  ssh_keys = [tls_private_key.storagebox[0].public_key_openssh]

  access_settings = {
    ssh_enabled          = true
    samba_enabled        = false
    webdav_enabled       = false
    reachable_externally = false
  }

  snapshot_plan = {
    hour          = 3
    minute        = 0
    max_snapshots = 7
  }

  labels = {
    managed = "terraform"
  }

  delete_protection = true

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}
