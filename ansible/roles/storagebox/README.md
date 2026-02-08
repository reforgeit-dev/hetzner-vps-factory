# Storage Box Role

Mounts Hetzner Storage Box via SSHFS.

## What It Does

- Installs SSHFS package
- Deploys Storage Box SSH private key
- Configures known_hosts for non-standard port
- Creates persistent fstab mount entry
- Mounts Storage Box at specified path
- Optionally creates directories on Storage Box

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `storagebox_ssh_private_key` | `""` | SSH private key (from Terraform) |
| `storagebox_server` | `""` | Storage Box hostname |
| `storagebox_username` | `""` | Storage Box username |
| `storagebox_ssh_port` | `23` | SSH port (Hetzner uses 23) |
| `storagebox_mount_point` | `/mnt/storagebox` | Local mount path |
| `storagebox_ssh_key_path` | `/root/.ssh/storagebox_key` | Key file location |
| `storagebox_directories` | `[]` | Directories to create after mount |

## Usage

```bash
# Run with credentials from Terraform
terraform -chdir=../terraform output -json | jq '{
  storagebox_ssh_private_key: .storagebox_ssh_private_key.value,
  storagebox_server: .storagebox_server.value,
  storagebox_username: .storagebox_username.value
}' > /tmp/storagebox_vars.json

ansible-playbook -i inventory.ini playbooks/site.yml -t storagebox \
  -e @/tmp/storagebox_vars.json
```

## Verification

```bash
df -h /mnt/storagebox
ls -la /mnt/storagebox
```

## Notes

- Hetzner Storage Box uses port 23 (not 22)
- Role is non-destructive: only adds storagebox-specific entries
- Existing SSH keys and known_hosts entries are preserved
- Mount includes auto-reconnect with keepalive
- The `deploy.sh` script handles credential passing automatically
- Mount uses FUSE `allow_other` option so Docker containers can access the Storage Box. This also enables `/etc/fuse.conf` `user_allow_other`. Required when bind-mounting storagebox paths into containers (e.g., Immich media library).
