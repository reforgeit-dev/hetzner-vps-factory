#!/bin/bash
# Phase 1 deployment script
# Orchestrates Terraform provisioning and Ansible configuration
#
# Usage: ./scripts/deploy.sh [options]
#
# Options:
#   --profile <name>  VPS profile (default: immich, matches group_vars/<name>.yml)
#   --skip-terraform  Skip Terraform entirely (use existing infrastructure)
#   --skip-ansible    Skip Ansible provisioning (Terraform only)
#   --quiet, -q       Quiet mode: minimal output, errors only (for automation)
#   --auto-approve    Auto-approve Terraform changes (use with --quiet)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Set up logging
mkdir -p "$REPO_ROOT/ansible/logs"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOG_FILE="$REPO_ROOT/ansible/logs/deploy_${TIMESTAMP}.log"
export ANSIBLE_LOG_PATH="$REPO_ROOT/ansible/logs/ansible_${TIMESTAMP}.log"

# Parse arguments
SKIP_TERRAFORM=false
SKIP_ANSIBLE=false
QUIET_MODE=false
AUTO_APPROVE=false
PROFILE="immich"

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --skip-ansible)
            SKIP_ANSIBLE=true
            shift
            ;;
        --quiet|-q)
            QUIET_MODE=true
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --reconfigure)
            SKIP_TERRAFORM=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--profile <name>] [--skip-terraform] [--skip-ansible] [--quiet] [--auto-approve]"
            exit 1
            ;;
    esac
done

# =============================================================================
# Logging functions
# =============================================================================

# Log to file and optionally to stdout
log() {
    echo "$@" >> "$LOG_FILE"
    if [ "$QUIET_MODE" != true ]; then
        echo "$@"
    fi
}

# Log header (always show in quiet mode too for progress indication)
log_header() {
    echo "$@" >> "$LOG_FILE"
    if [ "$QUIET_MODE" = true ]; then
        echo "[$(date +%H:%M:%S)] $1"
    else
        echo "$@"
    fi
}

# Log error (always show)
log_error() {
    echo "ERROR: $@" | tee -a "$LOG_FILE" >&2
}

# Log success marker
log_success() {
    log "✓ $@"
}

# Run command with output handling
# In quiet mode: capture output, only show on error
# In normal mode: show output normally
run_cmd() {
    local description="$1"
    shift

    log "Running: $@"

    if [ "$QUIET_MODE" = true ]; then
        local output
        local exit_code
        output=$("$@" 2>&1) && exit_code=0 || exit_code=$?
        echo "$output" >> "$LOG_FILE"

        if [ $exit_code -ne 0 ]; then
            log_error "$description failed (exit code: $exit_code)"
            log_error "Command: $@"
            log_error "Output:"
            echo "$output" >&2
            return $exit_code
        fi
        return 0
    else
        "$@"
    fi
}

# Run command and capture exit code without failing
run_cmd_no_fail() {
    local description="$1"
    shift

    log "Running: $@"

    if [ "$QUIET_MODE" = true ]; then
        local output
        local exit_code
        output=$("$@" 2>&1) && exit_code=0 || exit_code=$?
        echo "$output" >> "$LOG_FILE"
        return $exit_code
    else
        "$@" && return 0 || return $?
    fi
}

# =============================================================================
# Start deployment
# =============================================================================

log_header "Homelab IaC Deployment"
log "Started at: $(date)"
log "Log file: $LOG_FILE"
log ""

if [ "$QUIET_MODE" = true ]; then
    echo "Running in quiet mode. Full logs: $LOG_FILE"
    echo ""
fi

# Check prerequisites
log_header "Checking prerequisites..."

PREREQ_FAILED=false

if ! command -v terraform &> /dev/null; then
    log_error "terraform not found. Please install Terraform."
    PREREQ_FAILED=true
fi

if ! command -v ansible &> /dev/null; then
    log_error "ansible not found. Please install Ansible."
    PREREQ_FAILED=true
fi

if ! command -v jq &> /dev/null; then
    log_error "jq not found. Please install jq."
    PREREQ_FAILED=true
fi

if [ -z "$HCLOUD_TOKEN" ]; then
    log_error "HCLOUD_TOKEN environment variable not set"
    PREREQ_FAILED=true
fi

if [ -z "$TAILSCALE_AUTH_KEY" ]; then
    log_error "TAILSCALE_AUTH_KEY environment variable not set"
    PREREQ_FAILED=true
fi

if [ "$PREREQ_FAILED" = true ]; then
    exit 1
fi

log_success "All prerequisites met"
log ""

# =============================================================================
# TERRAFORM PHASE
# =============================================================================
if [ "$SKIP_TERRAFORM" = true ]; then
    log "Skipping Terraform (--skip-terraform)"
    log ""
else
    log_header "TERRAFORM"

    cd "$REPO_ROOT/terraform"

    # Step 1: Terraform init
    log "Initializing Terraform..."
    run_cmd "Terraform init" terraform init -input=false
    log_success "Terraform initialized"

    # Step 2: Terraform validate
    log "Validating configuration..."
    run_cmd "Terraform validate" terraform validate
    log_success "Configuration valid"

    # Step 3: Terraform plan
    log "Planning infrastructure changes..."

    PLAN_EXIT_CODE=0
    if [ "$QUIET_MODE" = true ]; then
        terraform plan -out=tfplan -detailed-exitcode -input=false >> "$LOG_FILE" 2>&1 || PLAN_EXIT_CODE=$?
    else
        terraform plan -out=tfplan -detailed-exitcode -input=false || PLAN_EXIT_CODE=$?
    fi

    if [ "$PLAN_EXIT_CODE" -eq 1 ]; then
        log_error "Terraform plan failed"
        exit 1
    elif [ "$PLAN_EXIT_CODE" -eq 0 ]; then
        log_success "No infrastructure changes needed"
    else
        log "Changes detected in plan"

        # Handle approval
        if [ "$QUIET_MODE" = true ]; then
            if [ "$AUTO_APPROVE" = true ]; then
                log "Auto-approving changes (--auto-approve)"
                run_cmd "Terraform apply" terraform apply -input=false tfplan
                log_success "Infrastructure provisioned"
            else
                log "Skipping apply in quiet mode (use --auto-approve to apply)"
            fi
        else
            echo ""
            read -p "Apply the plan? (yes/no): " -r
            echo ""
            if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                terraform apply tfplan
                log_success "Infrastructure provisioned"
            else
                log "Terraform apply cancelled"
            fi
        fi
    fi

    # Export outputs
    log "Exporting Terraform outputs..."
    terraform output -json > terraform_output.json 2>> "$LOG_FILE"
    log_success "Outputs exported"
    log ""

    cd "$REPO_ROOT"
fi

# =============================================================================
# INVENTORY GENERATION
# =============================================================================
log_header "INVENTORY GENERATION"

log "Auto-detecting server state (profile: $PROFILE)..."
if [ "$QUIET_MODE" = true ]; then
    bash "$SCRIPT_DIR/generate_inventory.sh" --profile "$PROFILE" >> "$LOG_FILE" 2>&1
else
    bash "$SCRIPT_DIR/generate_inventory.sh" --profile "$PROFILE"
fi
log_success "Inventory generated"
log ""

# =============================================================================
# CONNECTIVITY TEST
# =============================================================================
log_header "CONNECTIVITY TEST"

cd "$REPO_ROOT/ansible"
if run_cmd_no_fail "Ansible ping" ansible all -i inventory.ini -m ping; then
    log_success "Connectivity successful"
else
    log_error "Connectivity failed"
    log_error "Troubleshooting:"
    log_error "  1. Check if server is running (Hetzner Console)"
    log_error "  2. Check SSH key (~/.ssh/id_ed25519)"
    log_error "  3. Check Tailscale status (tailscale status)"
    log_error "  4. Try manual SSH to diagnose"
    exit 1
fi
log ""

# =============================================================================
# ANSIBLE PHASE
# =============================================================================
if [ "$SKIP_ANSIBLE" = true ]; then
    log "Skipping Ansible (--skip-ansible)"
    log ""
else
    log_header "ANSIBLE PROVISIONING"

    # Handle approval in interactive mode
    if [ "$QUIET_MODE" != true ]; then
        read -p "Run Ansible playbooks? (yes/no): " -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Ansible provisioning skipped"
            log "Run later with: ansible-playbook -i inventory.ini playbooks/site.yml"
            SKIP_ANSIBLE=true
        fi
    fi

    if [ "$SKIP_ANSIBLE" != true ]; then
        cd "$REPO_ROOT/ansible"

        # Storagebox credentials are in host_vars/ (generated by generate_inventory.sh)
        log "Running Ansible playbooks..."
        if [ "$QUIET_MODE" = true ]; then
            # In quiet mode, run without -v and capture output
            if ansible-playbook -i inventory.ini playbooks/site.yml >> "$LOG_FILE" 2>&1; then
                log_success "Ansible provisioning complete"
            else
                log_error "Ansible provisioning failed. Check log: $LOG_FILE"
                log_error "Ansible log: $ANSIBLE_LOG_PATH"
                exit 1
            fi
        else
            ansible-playbook -i inventory.ini playbooks/site.yml -v
            log_success "Ansible provisioning complete"
        fi
        log ""

        # Skip optional steps in quiet mode
        if [ "$QUIET_MODE" != true ]; then
            # Optional: Ubuntu upgrade
            TARGET_VERSION=$(grep 'ubuntu_target_version:' "$REPO_ROOT/ansible/roles/upgrade/defaults/main.yml" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/' || echo "")
            if [ -n "$TARGET_VERSION" ]; then
                CURRENT_VERSION=$(ansible all -i inventory.ini -m shell -a "lsb_release -rs" 2>/dev/null | grep -E "^[0-9]+\.[0-9]+" | head -1 || echo "unknown")

                if [ "$CURRENT_VERSION" != "$TARGET_VERSION" ] && [ "$CURRENT_VERSION" != "unknown" ]; then
                    echo ""
                    echo "Ubuntu upgrade available: $CURRENT_VERSION -> $TARGET_VERSION"
                    read -p "Upgrade Ubuntu? (yes/no): " -r
                    echo ""
                    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                        ansible-playbook -i inventory.ini playbooks/upgrade.yml -v
                        echo "Waiting for reboot..."
                        sleep 30
                        ansible all -i inventory.ini -m ping --retries=10 --delay=15 || true
                    fi
                fi
            fi

            # Optional: Hetzner firewall lockdown
            echo ""
            echo "Hetzner firewall lockdown blocks public SSH (Tailscale-only access)"
            read -p "Enable firewall lockdown? (yes/no): " -r
            echo ""
            if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                ansible-playbook -i inventory.ini playbooks/site.yml -t lockdown -e '{"enable_hetzner_firewall": true}' -v
                log_success "Firewall applied"

                cd "$REPO_ROOT"
                bash "$SCRIPT_DIR/generate_inventory.sh" --profile "$PROFILE"
                cd "$REPO_ROOT/ansible"

                if ansible all -i inventory.ini -m ping; then
                    log_success "Tailscale connectivity confirmed"
                else
                    log_error "Tailscale connectivity test failed"
                fi
            fi
        fi
    fi
fi

# =============================================================================
# DONE
# =============================================================================
log ""
log_header "DEPLOYMENT COMPLETE"

# Look in profile-specific group_vars first, then all.yml
PROFILE_VARS="$REPO_ROOT/ansible/group_vars/${PROFILE}.yml"
TAILSCALE_HOSTNAME=$(grep 'tailscale_hostname:' "$PROFILE_VARS" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/' || echo "")
if [ -z "$TAILSCALE_HOSTNAME" ]; then
    TAILSCALE_HOSTNAME=$(grep 'tailscale_hostname:' "$REPO_ROOT/ansible/group_vars/all.yml" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/' || echo "my-server")
fi
POWER_USER=$(grep 'power_user_name:' "$REPO_ROOT/ansible/group_vars/all.yml" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/' || echo "deploy")

log ""
log "Connect: ssh ${POWER_USER}@${TAILSCALE_HOSTNAME}"
log "Logs: $LOG_FILE"
log "Ansible log: $ANSIBLE_LOG_PATH"
log ""

if [ "$QUIET_MODE" = true ]; then
    echo ""
    echo "Deployment complete. Connect: ssh ${POWER_USER}@${TAILSCALE_HOSTNAME}"
    echo "Full logs: $LOG_FILE"
fi
