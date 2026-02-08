# Shared SSH key for Ansible provisioning (used by all VPS instances)
resource "hcloud_ssh_key" "ansible" {
  name       = "ansible-provisioning"
  public_key = file(var.ssh_public_key_path)
}

# =============================================================================
# VPS instances
# =============================================================================

module "vps" {
  source = "./modules/hetzner-vps"

  server_name     = var.server_name
  server_type     = var.server_type
  location        = var.location
  os_image        = var.os_image
  ssh_key_ids     = [hcloud_ssh_key.ansible.id]
  backups_enabled = var.backups_enabled

  storagebox_enabled = var.storagebox_enabled
  storagebox_type    = var.storagebox_type
}
