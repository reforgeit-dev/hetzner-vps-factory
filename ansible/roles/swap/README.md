# Swap Role

Configures a swap file to prevent OOM kills on memory-constrained VPS instances.

## What It Does

- Creates a swap file (default 4GB)
- Sets secure permissions (0600)
- Formats and enables swap
- Persists via fstab
- Tunes swappiness and vfs_cache_pressure via sysctl

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `install_swap` | `true` | Enable/disable this role |
| `swap_file_path` | `/swapfile` | Path for the swap file |
| `swap_file_size_mb` | `4096` | Swap file size in MB |
| `swap_swappiness` | `10` | How aggressively to use swap (0-100, low = prefer RAM) |
| `swap_vfs_cache_pressure` | `50` | How aggressively to reclaim inode/dentry caches |

## Usage

```bash
# Run only swap setup
ansible-playbook -i inventory.ini playbooks/site.yml -t swap

# Skip swap
ansible-playbook -i inventory.ini playbooks/site.yml -e 'install_swap=false'
```

## Verification

```bash
swapon --show
free -h
cat /proc/sys/vm/swappiness
```

## Notes

- This role is optional: set `install_swap: false` to skip
- Idempotent: skips creation if swap file already exists, skips swapon if swap is already active
- Swappiness of 10 means the kernel strongly prefers RAM and only swaps under pressure
- Sysctl settings persist in `/etc/sysctl.d/99-swap.conf`
