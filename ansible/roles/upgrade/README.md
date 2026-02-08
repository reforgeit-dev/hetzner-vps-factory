# Upgrade Role

Upgrades Ubuntu to a target release version, stepping through intermediate releases automatically.

## What It Does

- Deploys a bash script + systemd oneshot service to the remote server
- The service runs on each boot: fixes packages, runs `do-release-upgrade`, reboots
- Repeats until the target version is reached, then writes a completion marker
- Ansible polls for the marker (riding through reboots), then verifies and cleans up
- All post-upgrade Ansible tasks use `raw` (no Python dependency) to avoid ABI breakage

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ubuntu_target_version` | `"25.10"` | Target Ubuntu version |
| `max_upgrade_steps` | `5` | Max intermediate steps (prevents infinite loops) |
| `upgrade_timeout_minutes` | `60` | How long Ansible waits for the full upgrade |

## Usage

```bash
# Run upgrade playbook
ansible-playbook -i inventory.ini playbooks/upgrade.yml

# Override target version
ansible-playbook -i inventory.ini playbooks/upgrade.yml -e 'ubuntu_target_version=24.10'
```

## How It Works

1. Ansible deploys `/usr/local/bin/ubuntu-release-upgrade` script and a systemd service
2. Service starts and runs the script (non-blocking so Ansible isn't stuck)
3. Script on each boot cycle:
   - Fixes broken packages (`dpkg --configure -a`, `apt-get --fix-broken`)
   - Runs `apt-get dist-upgrade` to finalize any partial upgrade
   - Reboots if `/var/run/reboot-required` exists
   - Runs `do-release-upgrade -f DistUpgradeViewNonInteractive`
   - Reboots to activate the new release
4. On next boot, service runs again. If at target version, writes `/var/lib/ubuntu-upgrade-complete` and disables itself
5. Ansible detects the marker, reads the final version, cleans up all artifacts

## Upgrade Path Example

24.04 -> 25.10 requires 3 boot cycles:
1. Boot: 24.04 -> do-release-upgrade -> reboot
2. Boot: 24.10 -> fix packages -> do-release-upgrade -> reboot
3. Boot: 25.10 -> at target, write marker, done

## Verification

After the role completes, it displays:
```
Ubuntu upgraded: 24.04 -> 25.10 (SUCCESS: 25.10 >= 25.10)
```

If the target wasn't reached, the role fails with the result and points to the server log.

## Notes

- All upgrade logic is in a bash script (no Python dependency issues)
- Step counter prevents infinite reboot loops if an intermediate release is EOL
- Log file at `/var/log/ubuntu-release-upgrade.log` persists after cleanup for debugging
- Non-LTS targets automatically set `Prompt=normal` in `/etc/update-manager/release-upgrades`
- Ensure backups before upgrading
- Monitor via Hetzner Console if needed

## Caution

- Release upgrades can take significant time (multiply by number of steps)
- Test on non-production first
- Intermediate non-LTS releases may become EOL and block the upgrade path
