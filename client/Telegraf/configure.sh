#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TELEGRAF_CONF_SRC="${SCRIPT_DIR}/telegraf.conf"
TELEGRAF_CONF_DEST="/etc/telegraf/telegraf.conf"
TELEGRAF_DEFAULTS="/etc/default/telegraf"

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

# These run as if conditions, where set -e is suspended, so a failed sudo read
# must die explicitly rather than be mistaken for a negative answer.
defaults_file_defines_opts() {
    defaults_content="$(sudo cat "${TELEGRAF_DEFAULTS}")" || die "Failed to read ${TELEGRAF_DEFAULTS}"
    printf '%s\n' "${defaults_content}" | grep -Eq '^[[:space:]]*(export[[:space:]]+)?TELEGRAF_OPTS='
}

defaults_file_lacks_trailing_newline() {
    last_char="$(sudo tail -c 1 "${TELEGRAF_DEFAULTS}")" || die "Failed to read ${TELEGRAF_DEFAULTS}"
    [ -n "${last_char}" ]
}

create_empty_defaults_file() {
    info "Creating ${TELEGRAF_DEFAULTS}..."
    sudo install -o root -g root -m 0644 /dev/null "${TELEGRAF_DEFAULTS}" || die "Failed to create ${TELEGRAF_DEFAULTS}"
}

# Appending via tee -a keeps the existing file's ownership and permissions.
append_opts_to_defaults_file() {
    info "Adding TELEGRAF_OPTS to ${TELEGRAF_DEFAULTS}..."
    if defaults_file_lacks_trailing_newline; then
        printf '\n' | sudo tee -a "${TELEGRAF_DEFAULTS}" > /dev/null || die "Failed to update ${TELEGRAF_DEFAULTS}"
    fi
    printf 'TELEGRAF_OPTS=""\n' | sudo tee -a "${TELEGRAF_DEFAULTS}" > /dev/null || die "Failed to update ${TELEGRAF_DEFAULTS}"
    success "Added TELEGRAF_OPTS to ${TELEGRAF_DEFAULTS}"
}

# The InfluxData package unit expands $TELEGRAF_OPTS from this file and systemd
# warns on every start when it is undefined; the Arch unit references neither.
ensure_defaults_file() {
    if ! systemctl cat telegraf 2>/dev/null | grep -q "EnvironmentFile=-*${TELEGRAF_DEFAULTS}"; then
        info "Telegraf unit does not read ${TELEGRAF_DEFAULTS}, skipping defaults file."
        return 0
    fi

    if [ ! -e "${TELEGRAF_DEFAULTS}" ]; then
        create_empty_defaults_file
    elif defaults_file_defines_opts; then
        info "${TELEGRAF_DEFAULTS} already defines TELEGRAF_OPTS, leaving it unchanged."
        return 0
    fi

    append_opts_to_defaults_file
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
    # set -e is suspended inside a function called on the left of ||, so the
    # writes in these functions fail explicitly with || die.
    deploy_config || config_changed=1
    ensure_defaults_file || config_changed=1
    manage_service "${config_changed}"
    success "Telegraf configuration complete."
}

main
