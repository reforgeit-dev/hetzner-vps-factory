output "server_ipv4_address" {
  description = "Public IPv4 address of the VPS"
  value       = module.vps.server_ipv4_address
}

output "server_ipv6_address" {
  description = "Public IPv6 address of the VPS"
  value       = module.vps.server_ipv6_address
}

output "server_name" {
  description = "Hostname of the VPS"
  value       = module.vps.server_name
}

output "backups_enabled" {
  description = "Whether automatic backups are enabled"
  value       = var.backups_enabled
}

# Storage Box outputs
output "storagebox_server" {
  description = "Storage Box FQDN for SSHFS mount"
  value       = module.vps.storagebox_server
}

output "storagebox_username" {
  description = "Storage Box username"
  value       = module.vps.storagebox_username
}

output "storagebox_ssh_private_key" {
  description = "SSH private key for Storage Box access (deploy to VPS)"
  value       = module.vps.storagebox_ssh_private_key
  sensitive   = true
}

output "storagebox_password" {
  description = "Storage Box password (backup access method)"
  value       = module.vps.storagebox_password
  sensitive   = true
}
