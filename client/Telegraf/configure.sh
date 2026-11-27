#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TELEGRAF_CONF_SRC="${SCRIPT_DIR}/telegraf.conf"
TELEGRAF_CONF_DEST="/etc/telegraf/telegraf.conf"
TELEGRAF_DEFAULTS="/etc/default/telegraf"
TELEGRAF_SMART_SUDOERS="/etc/sudoers.d/telegraf-smart"
SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

die() {
    if [ -t 2 ]; then
        printf '\n\033[31m✗\033[0m %s\n' "$*" >&2
    else
        printf '\n✗ %s\n' "$*" >&2
    fi
    exit 1
}

success() {
    if [ -t 1 ]; then
        printf '\n\033[32m✓\033[0m %s\n' "$*"
    else
        printf '\n✓ %s\n' "$*"
    fi
}

info() {
    if [ -t 1 ]; then
        printf '\n\033[32m→\033[0m %s\n' "$*"
    else
        printf '\n→ %s\n' "$*"
    fi
}

# Returns true (0) when running inside a Claude Code Bash-tool session.
# Claude Code sets CLAUDECODE=1 in every shell it spawns via the Bash tool;
# that value is inherited by subprocesses (e.g. git hooks).
# Source: https://docs.anthropic.com/en/docs/claude-code/settings#environment-variables
is_ai_agent() {
    [ "${CLAUDECODE:-}" = "1" ]
}

# The checks run with a fixed system PATH rather than the invoking user's, so
# a user-writable directory early in that PATH cannot change what is found.
# install.sh's resolve_system_command uses the same list and must match it.
run_with_system_path() (
    PATH="${SYSTEM_PATH}"
    "$@"
)

system_command_exists() {
    run_with_system_path command -v "$1" >/dev/null 2>&1
}

# The sudoers directory is root-only, so the check runs as root; it reports the
# answer on stdout so a failed sudo dies rather than reading as "missing".
# install.sh writes the rule for the sudo installed at the time, so a host that
# later switches to sudo-rs keeps a classic-only line that sudo-rs rejects;
# visudo (which sudo-rs also ships) catches that as "invalid".
smart_sudoers_state() {
    sudo sh -c 'PATH="$2"; if [ ! -f "$1" ]; then echo missing; elif visudo -cf "$1" >/dev/null 2>&1; then echo valid; else echo invalid; fi' sh "${TELEGRAF_SMART_SUDOERS}" "${SYSTEM_PATH}"
}

# inputs.smart fails to initialise without smartctl, which makes the config
# check fail on hosts installed before it was added, so name the real fix.
require_smart_prerequisites() {
    if ! system_command_exists smartctl; then
        die "smartctl not found; run ./install.sh first (it installs smartmontools, nvme-cli and the telegraf SMART sudoers rule)"
    fi

    sudoers_state="$(smart_sudoers_state)" || die "Failed to check ${TELEGRAF_SMART_SUDOERS}"
    case "${sudoers_state}" in
        valid) ;;
        missing) die "${TELEGRAF_SMART_SUDOERS} not found; run ./install.sh first (it installs smartmontools, nvme-cli and the telegraf SMART sudoers rule)" ;;
        *) die "${TELEGRAF_SMART_SUDOERS} failed visudo validation (for example after switching to sudo-rs); re-run ./install.sh to regenerate it for the installed sudo" ;;
    esac
}

validate_config() {
    info "Validating Telegraf configuration..."

    if [ ! -f "${TELEGRAF_CONF_SRC}" ]; then
        die "telegraf.conf not found at ${TELEGRAF_CONF_SRC}"
    fi

    if ! system_command_exists telegraf; then
        die "telegraf not found; run install.sh first"
    fi

    require_smart_prerequisites

    if ! check_output="$(run_with_system_path telegraf config check --config "${TELEGRAF_CONF_SRC}" 2>&1)"; then
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
        info "Configuration changed, restarting Telegraf..."
        sudo systemctl restart telegraf
    elif ! sudo systemctl is-active --quiet telegraf; then
        info "Telegraf not running, starting..."
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
