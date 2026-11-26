#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: env command
# =============================================================================
# Check tools, create .env and show the environment.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# ---------------------------------------------------------------------------
# COMMAND: env
# ---------------------------------------------------------------------------
cmd_env_help() {
    cat <<'EOF'
kubewekend env - Environment management

SUBCOMMANDS
  check         Check required tools are installed
  init          Create .env from template.env
  show          Print current environment variables

EXAMPLES
  ./scripts/setup.sh env check
  ./scripts/setup.sh env init
EOF
}

cmd_env() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        check) env_check ;;
        init)  env_init ;;
        show)  env_show ;;
        *)     cmd_env_help ;;
    esac
}

env_check() {
    header "Checking required tools"
    local tools=(vagrant virtualbox ansible ansible-playbook ssh kubectl helm)
    local optional=(kind k3s docker jq yq)
    local missing=0

    for t in "${tools[@]}"; do
        if command -v "$t" &>/dev/null; then
            info "$t  $(command -v "$t")"
        else
            warn "$t  NOT FOUND (required)"
            missing=$((missing + 1))
        fi
    done

    printf "\n"
    info "Optional tools:"
    for t in "${optional[@]}"; do
        if command -v "$t" &>/dev/null; then
            info "$t  $(command -v "$t")"
        else
            warn "$t  not found (optional)"
        fi
    done

    if [[ $missing -gt 0 ]]; then
        error "$missing required tool(s) missing"
        return 1
    fi
    info "All required tools are available!"
}

env_init() {
    if [[ -f "$ENV_FILE" ]]; then
        warn ".env already exists"
        confirm "Overwrite?" || return 0
    fi
    cp "$TEMPLATE_ENV" "$ENV_FILE"
    info "Created .env from template.env - please edit it with your values"
}

env_show() {
    load_env
    header "Environment"
    echo "SSH_USER          = ${SSH_USER:-<not set>}"
    echo "SSH_KEY           = ${SSH_KEY:-<not set>}"
    echo "PROJECT_ROOT      = $PROJECT_ROOT"
    echo "ANSIBLE_DIR       = $ANSIBLE_DIR"
    echo "INVENTORY         = $HOSTS_FILE"
}
