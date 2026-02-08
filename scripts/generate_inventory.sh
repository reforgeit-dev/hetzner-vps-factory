#!/bin/bash
# Generate Ansible inventory and host_vars from Terraform outputs
# Usage: ./scripts/generate_inventory.sh [--mode initial|configured|auto] [--profile <name>]
#
# Modes:
#   initial    - Use public IP and root user (fresh provisioning)
#   configured - Use Tailscale hostname and power user (after hardening)
#   auto       - Auto-detect by testing actual SSH connectivity (default)
#
# Profile:
#   Name of the VPS profile (matches group_vars/<profile>.yml)
#   Default: immich

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_OUTPUT_FILE="${REPO_ROOT}/terraform/terraform_output.json"
INVENTORY_FILE="${REPO_ROOT}/ansible/inventory.ini"
HOST_VARS_DIR="${REPO_ROOT}/ansible/host_vars"

# SSH timeout for connectivity tests
SSH_TIMEOUT=5

# Retry settings for auto-detect mode (new VPS may need time to boot)
MAX_RETRIES=3
RETRY_DELAY=10

# Parse arguments
MODE="auto"
PROFILE="immich"
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--mode initial|configured|auto] [--profile <name>]"
            exit 1
            ;;
    esac
done

if [ ! -f "$TERRAFORM_OUTPUT_FILE" ]; then
    echo "Error: Terraform output file not found at $TERRAFORM_OUTPUT_FILE"
    echo ""
    echo "Please run the following first:"
    echo "  cd terraform"
    echo "  terraform output -json > terraform_output.json"
    echo "  cd .."
    exit 1
fi

# Extract values from Terraform output
SERVER_IP=$(jq -r '.server_ipv4_address.value' "$TERRAFORM_OUTPUT_FILE" 2>/dev/null || echo "")
SERVER_NAME=$(jq -r '.server_name.value' "$TERRAFORM_OUTPUT_FILE" 2>/dev/null || echo "my-server")

if [ -z "$SERVER_IP" ] || [ "$SERVER_IP" == "null" ]; then
    echo "Error: Could not extract server IP from Terraform output"
    echo "Make sure you have run 'terraform apply' successfully"
    exit 1
fi

# Resolve group_vars for this profile
# Look in profile-specific file first, then all.yml
resolve_var() {
    local var_name="$1"
    local default_val="$2"
    local val=""

    # Profile-specific group_vars
    local profile_vars="$REPO_ROOT/ansible/group_vars/${PROFILE}.yml"
    if [ -f "$profile_vars" ]; then
        val=$(grep "^${var_name}:" "$profile_vars" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/' || echo "")
    fi

    # Fallback to all.yml
    if [ -z "$val" ]; then
        val=$(grep "^${var_name}:" "$REPO_ROOT/ansible/group_vars/all.yml" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/' || echo "")
    fi

    echo "${val:-$default_val}"
}

TAILSCALE_HOSTNAME=$(resolve_var "tailscale_hostname" "$SERVER_NAME")
POWER_USER=$(resolve_var "power_user_name" "deploy")

# Test SSH connectivity - returns 0 if successful
test_ssh() {
    local host="$1"
    local user="$2"
    timeout "$SSH_TIMEOUT" ssh \
        -o ConnectTimeout="$SSH_TIMEOUT" \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -o LogLevel=ERROR \
        "$user@$host" "exit" 2>/dev/null
}

# Auto-detect server state by testing actual SSH connectivity
# Priority order:
#   1. Tailscale + power user (fully configured)
#   2. Public IP + power user (configured but firewall not applied)
#   3. Public IP + root (fresh VPS)
# Diagnostic messages go to stderr, only result goes to stdout
detect_server_state() {
    echo "Auto-detecting server state via SSH connectivity tests..." >&2
    echo "" >&2

    # Test 1: Tailscale + power user (ideal state)
    echo "  Testing: $POWER_USER@$TAILSCALE_HOSTNAME (Tailscale)..." >&2
    if test_ssh "$TAILSCALE_HOSTNAME" "$POWER_USER"; then
        echo "    ✓ Success - using Tailscale + power user" >&2
        echo "configured:tailscale"
        return
    else
        echo "    ✗ Failed" >&2
    fi

    # Test 2: Public IP + power user (configured but not locked down)
    echo "  Testing: $POWER_USER@$SERVER_IP (public IP)..." >&2
    if test_ssh "$SERVER_IP" "$POWER_USER"; then
        echo "    ✓ Success - using public IP + power user" >&2
        echo "configured:public"
        return
    else
        echo "    ✗ Failed" >&2
    fi

    # Test 3: Public IP + root (fresh VPS)
    echo "  Testing: root@$SERVER_IP (public IP)..." >&2
    if test_ssh "$SERVER_IP" "root"; then
        echo "    ✓ Success - using public IP + root (initial mode)" >&2
        echo "initial:public"
        return
    else
        echo "    ✗ Failed" >&2
    fi

    # All tests failed
    echo "" >&2
    echo "error"
}

# Determine actual mode
if [ "$MODE" == "auto" ]; then
    for attempt in $(seq 1 "$MAX_RETRIES"); do
        DETECTION_RESULT=$(detect_server_state)
        DETECTED_MODE=$(echo "$DETECTION_RESULT" | tail -1 | cut -d: -f1)
        DETECTED_METHOD=$(echo "$DETECTION_RESULT" | tail -1 | cut -d: -f2)

        if [ "$DETECTED_MODE" != "error" ]; then
            break
        fi

        if [ "$attempt" -lt "$MAX_RETRIES" ]; then
            echo "  Waiting for SSH to become available... (attempt $((attempt + 1))/$MAX_RETRIES)"
            sleep "$RETRY_DELAY"
        fi
    done

    if [ "$DETECTED_MODE" == "error" ]; then
        echo ""
        echo "Error: Could not connect to server via any method after $MAX_RETRIES attempts"
        echo ""
        echo "Tried:"
        echo "  - $POWER_USER@$TAILSCALE_HOSTNAME (Tailscale)"
        echo "  - $POWER_USER@$SERVER_IP (public IP)"
        echo "  - root@$SERVER_IP (public IP)"
        echo ""
        echo "Please verify:"
        echo "  1. Server is running (check Hetzner Console)"
        echo "  2. SSH key is correct (~/.ssh/id_ed25519)"
        echo "  3. Tailscale is connected (if using Tailscale)"
        echo "  4. Network connectivity to $SERVER_IP"
        exit 1
    fi

    MODE="$DETECTED_MODE"
    echo ""
fi

echo "Generating Ansible inventory (mode: $MODE, profile: $PROFILE)..."

# Generate inventory based on mode
if [ "$MODE" == "configured" ]; then
    # Determine best host to use
    # Prefer Tailscale if it worked, otherwise use public IP
    if [ "$DETECTED_METHOD" == "tailscale" ]; then
        ANSIBLE_HOST="$TAILSCALE_HOSTNAME"
        HOST_COMMENT="Tailscale"
    else
        ANSIBLE_HOST="$SERVER_IP"
        HOST_COMMENT="public IP (Tailscale not reachable)"
    fi

    cat > "$INVENTORY_FILE" << EOF
# Auto-generated Ansible inventory from Terraform outputs
# Generated: $(date)
# Mode: configured (power user access)
# Profile: $PROFILE
# Server: $SERVER_NAME
# Connection: $HOST_COMMENT

[$PROFILE]
$SERVER_NAME ansible_host=$ANSIBLE_HOST ansible_user=$POWER_USER

[hetzner_vps:children]
$PROFILE

[hetzner_vps:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args='-o ConnectTimeout=10 -o StrictHostKeyChecking=no'
ansible_become=true
EOF

    echo "✓ Inventory generated (configured mode)"
    echo ""
    echo "Server details:"
    echo "  Name: $SERVER_NAME"
    echo "  Profile: $PROFILE"
    echo "  Connect via: $ANSIBLE_HOST ($HOST_COMMENT)"
    echo "  User: $POWER_USER"
    echo "  Public IP: $SERVER_IP"
else
    # Initial mode: Public IP + root
    cat > "$INVENTORY_FILE" << EOF
# Auto-generated Ansible inventory from Terraform outputs
# Generated: $(date)
# Mode: initial (public IP access for provisioning)
# Profile: $PROFILE
# Server: $SERVER_NAME
# IP: $SERVER_IP

[$PROFILE]
$SERVER_NAME ansible_host=$SERVER_IP ansible_user=root

[hetzner_vps:children]
$PROFILE

[hetzner_vps:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args='-o ConnectTimeout=10 -o StrictHostKeyChecking=no'
EOF

    echo "✓ Inventory generated (initial mode)"
    echo ""
    echo "Server details:"
    echo "  Name: $SERVER_NAME"
    echo "  Profile: $PROFILE"
    echo "  IP: $SERVER_IP"
    echo "  User: root"
fi

# =============================================================================
# Generate host_vars from Terraform outputs (storagebox credentials)
# =============================================================================

STORAGEBOX_SERVER=$(jq -r '.storagebox_server.value // ""' "$TERRAFORM_OUTPUT_FILE" 2>/dev/null || echo "")
STORAGEBOX_USERNAME=$(jq -r '.storagebox_username.value // ""' "$TERRAFORM_OUTPUT_FILE" 2>/dev/null || echo "")
STORAGEBOX_SSH_KEY=$(jq -r '.storagebox_ssh_private_key.value // ""' "$TERRAFORM_OUTPUT_FILE" 2>/dev/null || echo "")

if [ -n "$STORAGEBOX_SERVER" ] && [ "$STORAGEBOX_SERVER" != "" ]; then
    mkdir -p "$HOST_VARS_DIR"

    {
        echo "---"
        echo "# Auto-generated from Terraform outputs — do not edit"
        echo "# Re-generate with: ./scripts/generate_inventory.sh"
        echo ""
        echo "storagebox_server: \"$STORAGEBOX_SERVER\""
        echo "storagebox_username: \"$STORAGEBOX_USERNAME\""
        echo "storagebox_ssh_private_key: |"
        echo "$STORAGEBOX_SSH_KEY" | sed 's/^/  /'
    } > "$HOST_VARS_DIR/${SERVER_NAME}.yml"

    echo ""
    echo "✓ Host vars generated: host_vars/${SERVER_NAME}.yml"
fi

echo ""
echo "Inventory file: $INVENTORY_FILE"
echo ""
echo "Test connectivity with:"
echo "  ansible all -i ansible/inventory.ini -m ping"
