# Users Role

Creates and configures system users for administration and services.

## What It Does

- Creates power user (human admin) with sudo access
- Creates apps user (service account) for running containers
- Deploys SSH public key for power user
- Optionally disables root SSH login

## Variables

### Power User (Admin)

| Variable | Default | Description |
|----------|---------|-------------|
| `power_user_name` | `"deploy"` | Username |
| `power_user_shell` | `"/bin/bash"` | Login shell |
| `power_user_groups` | `[sudo, docker]` | Group memberships |
| `power_user_ssh_key` | `~/.ssh/id_ed25519.pub` | SSH public key path |
| `power_user_passwordless_sudo` | `true` | Passwordless sudo |

### Apps User (Service Account)

| Variable | Default | Description |
|----------|---------|-------------|
| `apps_user_name` | `"apps"` | Username |
| `apps_user_shell` | `"/usr/sbin/nologin"` | No login shell |
| `apps_user_home` | `"/opt/apps"` | Home directory |
| `apps_user_groups` | `[docker]` | Group memberships |
| `apps_directories` | See defaults | Directories to create |

### Security

| Variable | Default | Description |
|----------|---------|-------------|
| `disable_root_ssh` | `false` | Disable root SSH login |

## Usage

```bash
# Run only user setup
ansible-playbook -i inventory.ini playbooks/site.yml -t users
```

## Notes

- Power user can run docker and sudo without password
- Apps user has nologin shell for security
- Set `disable_root_ssh: true` AFTER verifying power user works
- Root SSH is kept enabled initially to prevent lockout
