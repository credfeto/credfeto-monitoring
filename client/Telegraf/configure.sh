#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TELEGRAF_CONF_SRC="${SCRIPT_DIR}/telegraf.conf"
TELEGRAF_CONF_DEST="/etc/telegraf/telegraf.conf"

die() {
    printf '\n\033[31m✗\033[0m %s\n' "$*" >&2
    exit 1
}

success() {
    printf '\n\033[32m✓\033[0m %s\n' "$*"
}

info() {
    printf '\n\033[32m→\033[0m %s\n' "$*"
}

# Returns true (0) when running inside a Claude Code Bash-tool session.
# Claude Code sets CLAUDECODE=1 in every shell it spawns via the Bash tool;
# that value is inherited by subprocesses (e.g. git hooks).
# Source: https://docs.anthropic.com/en/docs/claude-code/settings#environment-variables
is_ai_agent() {
    [ "${CLAUDECODE:-}" = "1" ]
}

validate_config() {
    info "Validating Telegraf configuration..."

    if [ ! -f "${TELEGRAF_CONF_SRC}" ]; then
        die "telegraf.conf not found at ${TELEGRAF_CONF_SRC}"
    fi

    if ! command -v telegraf >/dev/null 2>&1; then
        die "telegraf not found; run install.sh first"
    fi

    if ! check_output="$(telegraf config check --config "${TELEGRAF_CONF_SRC}" 2>&1)"; then
        die "Telegraf rejected ${TELEGRAF_CONF_SRC}:
${check_output}"
    fi

    success "Configuration is valid."
}

deploy_config() {
    info "Deploying Telegraf configuration..."

    if cmp -s "${TELEGRAF_CONF_SRC}" "${TELEGRAF_CONF_DEST}" 2>/dev/null; then
        info "Configuration unchanged, skipping deploy."
        return 0
    fi

    sudo install -o root -g root -m 0644 "${TELEGRAF_CONF_SRC}" "${TELEGRAF_CONF_DEST}" || die "Failed to deploy configuration to ${TELEGRAF_CONF_DEST}"
    success "Configuration deployed to ${TELEGRAF_CONF_DEST}"
    return 1
}

manage_service() {
    config_changed="$1"

    info "Enabling Telegraf service..."
    sudo systemctl enable telegraf

    if [ "${config_changed}" = "1" ]; then
        info "Configuration changed — restarting Telegraf..."
        sudo systemctl restart telegraf
    elif ! sudo systemctl is-active --quiet telegraf; then
        info "Telegraf not running — starting..."
        sudo systemctl start telegraf
    else
        info "Telegraf already running with unchanged config, skipping restart."
    fi

    success "Telegraf service is active."
}

main() {
    config_changed=0
    validate_config
    deploy_config || config_changed=1
    manage_service "${config_changed}"
    success "Telegraf configuration complete."
}

main
