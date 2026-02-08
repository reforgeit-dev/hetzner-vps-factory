# Docker Role

Installs Docker Engine and Docker Compose V2.

## What It Does

- Adds Docker official GPG key and repository
- Installs Docker CE, CLI, containerd, and plugins
- Configures JSON logging with rotation
- Adds power user to docker group

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `docker_log_driver` | `"json-file"` | Docker logging driver |
| `docker_log_max_size` | `"10m"` | Max log file size |
| `docker_log_max_file` | `"3"` | Number of log files to keep |
| `docker_packages` | See defaults | Docker packages to install |

## Usage

```bash
# Run only Docker setup
ansible-playbook -i inventory.ini playbooks/site.yml -t docker

# Skip Docker installation
ansible-playbook -i inventory.ini playbooks/site.yml -e 'install_docker=false'
```

## Verification

```bash
docker --version
docker compose version
docker ps
```

## Templates

- `templates/daemon.json.j2` - Docker daemon configuration

## Notes

- This role is optional: set `install_docker: false` to skip
- Log rotation prevents disk fill from container logs
- Power user can run docker without sudo
