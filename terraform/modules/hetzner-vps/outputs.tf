output "server_ipv4_address" {
  description = "Public IPv4 address of the VPS"
  value       = hcloud_server.this.ipv4_address
}

output "server_ipv6_address" {
  description = "Public IPv6 address of the VPS"
  value       = hcloud_server.this.ipv6_address
}

output "server_name" {
  description = "Hostname of the VPS"
  value       = hcloud_server.this.name
}

output "server_id" {
  description = "Hetzner Cloud server ID"
  value       = hcloud_server.this.id
}

# Storage Box outputs (empty when disabled)

output "storagebox_server" {
  description = "Storage Box FQDN for SSHFS mount"
  value       = var.storagebox_enabled ? hcloud_storage_box.this[0].server : ""
}

output "storagebox_username" {
  description = "Storage Box username"
  value       = var.storagebox_enabled ? hcloud_storage_box.this[0].username : ""
}

output "storagebox_ssh_private_key" {
  description = "SSH private key for Storage Box access (deploy to VPS)"
  value       = var.storagebox_enabled ? tls_private_key.storagebox[0].private_key_openssh : ""
  sensitive   = true
}

output "storagebox_password" {
  description = "Storage Box password (backup access method)"
  value       = var.storagebox_enabled ? random_password.storagebox[0].result : ""
  sensitive   = true
}
