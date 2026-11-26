#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: status command
# =============================================================================
# Overall project status.
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# ---------------------------------------------------------------------------
# COMMAND: status
# ---------------------------------------------------------------------------
cmd_status() {
    header "Kubewekend Project Status"

    echo "Project Root: $PROJECT_ROOT"
    echo ""

    # Vagrant VMs
    if command -v vagrant &>/dev/null; then
        echo "${BOLD}Vagrant VMs:${NC}"
        cd "$PROJECT_ROOT"
        vagrant status 2>/dev/null | grep -E "running|poweroff|not created" | sed 's/^/  /'
        echo ""
    fi

    # Inventory
    echo "${BOLD}Ansible Inventory:${NC}"
    if [[ -f "$HOSTS_FILE" ]]; then
        grep -E "^\[|ansible_host" "$HOSTS_FILE" | sed 's/^/  /'
    else
        echo "  No inventory file"
    fi
    echo ""

    # Kubernetes clusters
    if command -v kubectl &>/dev/null; then
        echo "${BOLD}Kubernetes Contexts:${NC}"
        kubectl config get-contexts 2>/dev/null | head -10 | sed 's/^/  /' || echo "  No contexts"
        echo ""
    fi

    # Docker (for Kind)
    if command -v docker &>/dev/null; then
        echo "${BOLD}Docker Containers (kind):${NC}"
        docker ps --filter "label=io.x-k8s.kind.cluster" --format "  {{.Names}} ({{.Status}})" 2>/dev/null || echo "  No kind containers"
        echo ""
    fi
}
