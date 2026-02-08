# Immich (Coolify + photo library) deployment
# Usage: terraform apply -var-file=envs/immich.tfvars

server_name        = "my-immich-server"
server_type        = "cx33"
location           = "hel1"
os_image           = "ubuntu-24.04"
backups_enabled    = true
storagebox_enabled = true
storagebox_type    = "bx11"
