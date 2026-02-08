# Common Role

Base system configuration: package management and unattended upgrades.

## What It Does

- Updates apt cache
- Runs full dist-upgrade to patch all stale packages
- Installs base system packages
- Configures automatic security updates with optional auto-reboot

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `apt_upgrade_on_provision` | `true` | Run full dist-upgrade during provisioning |
| `apt_packages` | `[curl, ufw, unattended-upgrades, tmux]` | Packages to install |
| `unattended_upgrades_enabled` | `true` | Enable automatic updates |
| `unattended_upgrades_auto_reboot` | `true` | Auto-reboot after kernel updates |
| `unattended_upgrades_reboot_time` | `"03:00"` | Reboot time (24h format) |
| `unattended_upgrades_autoremove` | `true` | Remove unused dependencies |
| `unattended_upgrades_autoclean_interval` | `7` | Days between apt autoclean runs |

## Usage

```bash
# Run only common setup
ansible-playbook -i inventory.ini playbooks/site.yml -t common
```

## Templates

- `templates/20auto-upgrades.j2` - APT periodic update configuration

## Notes

- SSH hardening is in the dedicated `ssh` role
- fail2ban is in the dedicated `fail2ban` role
- Auto-reboot at 03:00 minimizes disruption
