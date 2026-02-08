# Upgrade Role

Upgrades Ubuntu to a target release version.

## What It Does

- Checks current Ubuntu version
- Runs `do-release-upgrade` if upgrade is available
- Handles release upgrade process non-interactively

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ubuntu_target_version` | `"25.10"` | Target Ubuntu version |

## Usage

```bash
# Run upgrade playbook
ansible-playbook -i inventory.ini playbooks/upgrade.yml

# Check current version
lsb_release -a
```

## Notes

- Ubuntu only allows upgrading to the next release (no skipping)
- Example path: 24.04 → 24.10 → 25.04 → 25.10
- Server will reboot after upgrade
- `do-release-upgrade` disconnects SSH temporarily
- May need to run multiple times to reach target version
- Ensure backups before upgrading

## Caution

- Release upgrades can take significant time
- Test on non-production first
- Monitor via Hetzner Console if SSH disconnects
