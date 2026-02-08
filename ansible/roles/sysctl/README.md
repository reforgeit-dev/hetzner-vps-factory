# Sysctl Role

Kernel hardening via sysctl parameters.

## What It Does

- Applies network security hardening (SYN cookies, no redirects, etc.)
- Applies kernel security hardening (ASLR, restricted ptrace, etc.)
- Applies filesystem hardening (protected symlinks/hardlinks)
- Persists settings to `/etc/sysctl.d/99-hardening.conf`

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `sysctl_hardening_enabled` | `true` | Enable/disable hardening |
| `sysctl_network_hardening` | See defaults | Network security params |
| `sysctl_kernel_hardening` | See defaults | Kernel security params |
| `sysctl_fs_hardening` | See defaults | Filesystem security params |
| `sysctl_custom` | `{}` | Custom additional params |

## Key Settings

### Network Security
- `net.ipv4.tcp_syncookies: 1` - SYN flood protection
- `net.ipv4.conf.all.rp_filter: 1` - Reverse path filtering
- `net.ipv4.conf.all.accept_redirects: 0` - Prevent MITM

### Kernel Security
- `kernel.randomize_va_space: 2` - Full ASLR
- `kernel.dmesg_restrict: 1` - Root-only dmesg
- `kernel.yama.ptrace_scope: 1` - Restrict ptrace

### Filesystem Security
- `fs.protected_symlinks: 1` - Prevent symlink attacks
- `fs.protected_hardlinks: 1` - Prevent hardlink attacks

## Usage

```bash
# Run only sysctl hardening
ansible-playbook -i inventory.ini playbooks/site.yml -t sysctl

# Verify settings
sysctl kernel.randomize_va_space
sysctl net.ipv4.tcp_syncookies
```

## Notes

- Settings persist across reboots via `/etc/sysctl.d/`
- Docker may reset some network settings on bridge creation (expected)
- Set `sysctl_hardening_enabled: false` to disable entirely
