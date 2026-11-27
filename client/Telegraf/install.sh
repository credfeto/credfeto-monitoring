#!/bin/sh
set -eu

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

# Prints the primary key fingerprint of a key file, or nothing if the file is
# missing or unparsable.
key_fingerprint() {
    gpg --show-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'
}

setup_influxdata_apt_repo() {
    info "Adding InfluxData apt repository..."

    # The old install left this file behind; a repository still configured to
    # trust it fails apt-get update with NO_PUBKEY once InfluxData rotates keys.
    # Removed unconditionally (not just when telegraf is missing) so a host that
    # already has telegraf installed is repaired too, rather than left with a
    # sources entry pointing at a keyring file that no longer exists.
    sudo rm -f /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg

    # Verified directly against https://repos.influxdata.com/influxdata-archive.key
    # with `gpg --show-keys --with-colons`; this is the primary key fingerprint,
    # which stays constant across InfluxData's subkey rotations (see issue #22).
    influxdata_key_fingerprint="24C975CBA61A024EE1B631787C3D57159FC2F927"
    keyring_path="/etc/apt/keyrings/influxdata-archive.gpg"
    sources_list="/etc/apt/sources.list.d/influxdata.list"
    sources_list_line="deb [arch=$(dpkg --print-architecture) signed-by=${keyring_path}] https://repos.influxdata.com/ubuntu stable main"
    export GNUPGHOME="${work_dir}/gnupg"
    mkdir -m 0700 "${GNUPGHOME}"

    # Skip the network fetch when the installed keyring is already the verified
    # key, so re-running this script on an already-repaired host is a no-op here.
    if [ "$(key_fingerprint "${keyring_path}")" != "${influxdata_key_fingerprint}" ]; then
        curl -fsSL https://repos.influxdata.com/influxdata-archive.key -o "${work_dir}/key.asc"

        actual_fingerprint=$(key_fingerprint "${work_dir}/key.asc")
        if [ "${actual_fingerprint}" != "${influxdata_key_fingerprint}" ]; then
            die "InfluxData signing key fingerprint mismatch: expected ${influxdata_key_fingerprint}, got ${actual_fingerprint:-<none>}"
        fi

        # Import then re-export by the verified fingerprint, rather than
        # dearmoring the downloaded file wholesale: this guarantees only the
        # pinned key's material reaches the trusted keyring even if the
        # response ever bundled the legitimate key alongside another one.
        gpg --quiet --import "${work_dir}/key.asc"
        gpg --yes --output "${work_dir}/key.gpg" --export "${influxdata_key_fingerprint}"

        sudo install -d -m 0755 /etc/apt/keyrings
        sudo install -m 0644 "${work_dir}/key.gpg" "${keyring_path}"
    fi

    if [ "$(cat "${sources_list}" 2>/dev/null)" != "${sources_list_line}" ]; then
        echo "${sources_list_line}" | sudo tee "${sources_list}" > /dev/null
    fi
}

apt_package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q '^ii'
}

# Package lists are refreshed only when a requested package is missing.
install_apt_packages() {
    for package in "$@"; do
        shift
        if apt_package_installed "${package}"; then
            info "${package} already installed, skipping package install."
        else
            set -- "$@" "${package}"
        fi
    done

    if [ "$#" -gt 0 ]; then
        sudo apt-get update -qq
        sudo apt-get install -y "$@"
    fi
}

install_pacman_packages() {
    for package in "$@"; do
        shift
        if pacman -Qi "${package}" > /dev/null 2>&1; then
            info "${package} already installed, skipping package install."
        else
            set -- "$@" "${package}"
        fi
    done

    if [ "$#" -gt 0 ]; then
        sudo pacman -S --noconfirm "$@"
    fi
}

install_ubuntu() {
    info "Installing Telegraf and SMART tools on Ubuntu/Debian..."
    setup_influxdata_apt_repo
    install_apt_packages telegraf smartmontools nvme-cli
}

install_arch() {
    info "Installing Telegraf and SMART tools on Arch Linux..."
    install_pacman_packages telegraf smartmontools nvme-cli
}

detect_and_install() {
    if command -v apt-get > /dev/null 2>&1; then
        install_ubuntu
    elif command -v pacman > /dev/null 2>&1; then
        install_arch
    else
        die "Unsupported package manager — only apt (Ubuntu/Debian) and pacman (Arch) are supported."
    fi
}

add_telegraf_to_docker_group() {
    info "Adding telegraf user to docker group for Docker stats collection..."
    if getent group docker > /dev/null 2>&1; then
        if ! id telegraf 2>/dev/null | grep -q '(docker)'; then
            sudo usermod -aG docker telegraf
            success "Added telegraf to docker group."
        else
            info "telegraf already in docker group, skipping."
        fi
    else
        info "docker group not found — skipping. Docker stats will not be available until Docker is installed and the group exists."
    fi
}

# Only plain absolute paths are allowed into the sudoers rule: whitespace,
# commas, wildcards, colons, backslashes and similar are sudoers syntax and
# could widen the rule beyond the single binary intended.
require_sudoers_safe_path() {
    case "$1" in
        /*) ;;
        *) die "Refusing to add non-absolute path to sudoers: $1" ;;
    esac
    case "$1" in
        *[!/._+0-9A-Za-z-]*) die "Refusing to add path with unsafe characters to sudoers: $1" ;;
    esac
}

# Resolved against the systemd default service PATH rather than the caller's,
# so the rule names the binary Telegraf's service will actually run, and a
# user-writable directory early in the caller's PATH cannot end up trusted.
resolve_system_command() (
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    command -v "$1"
)

install_telegraf_smart_sudoers() {
    info "Granting telegraf passwordless sudo for read-only smartctl queries..."

    sudoers_path="/etc/sudoers.d/telegraf-smart"
    smartctl_path=$(resolve_system_command smartctl) || die "smartctl not found after installing smartmontools."
    require_sudoers_safe_path "${smartctl_path}"

    # Each entry is the exact argv Telegraf's inputs.smart runs (`sudo -n` plus
    # the scans and the per-device query), so telegraf cannot use sudo to run
    # smartctl self-tests or --set, or nvme-cli's format/sanitize/write.
    # - nvme is left out: inputs.smart only runs it when enable_extensions is
    #   set, which telegraf.conf does not do.
    # - Devices are matched with single-character classes, never `*`: sudoers
    #   wildcards match across spaces, so `/dev/*` would also allow extra
    #   options appended after the device path.
    # - `=` must be escaped in sudoers command arguments.
    # - The Defaults! line stops sudo writing a log entry and a PAM session
    #   for every poll, as the inputs.smart README recommends.
    candidate="${work_dir}/telegraf-smart.sudoers"
    smartctl_query="${smartctl_path} --info --health --attributes --tolerance\\=verypermissive -n standby --format\\=brief"
    cat > "${candidate}" <<EOF
# Installed by credfeto-monitoring client/Telegraf/install.sh: read-only
# smartctl queries for Telegraf's inputs.smart (use_sudo = true).
Cmnd_Alias TELEGRAF_SMARTCTL = ${smartctl_path} --scan, \\
    ${smartctl_path} --scan --device\\=nvme, \\
    ${smartctl_query} /dev/sd[a-z], \\
    ${smartctl_query} /dev/sd[a-z][a-z], \\
    ${smartctl_query} /dev/nvme[0-9], \\
    ${smartctl_query} /dev/nvme[0-9][0-9]
telegraf ALL=(root) NOPASSWD: TELEGRAF_SMARTCTL
Defaults!TELEGRAF_SMARTCTL !logfile, !syslog, !pam_session
EOF

    # The installed file is readable by root only, so the comparison runs as root.
    if sudo cmp -s "${candidate}" "${sudoers_path}"; then
        info "telegraf SMART sudoers rule already up to date, skipping."
        return
    fi

    sudo visudo -cf "${candidate}" > /dev/null || die "Generated sudoers rule failed visudo validation."
    sudo install -o root -g root -m 0440 "${candidate}" "${sudoers_path}"
    success "Installed ${sudoers_path}."
}

main() {
    # A single EXIT trap covers every temporary file, because POSIX sh keeps
    # only one handler per condition and a later trap would replace this one.
    work_dir=$(mktemp -d)
    trap 'rm -rf "${work_dir}"' EXIT

    detect_and_install
    install_telegraf_smart_sudoers
    add_telegraf_to_docker_group
    success "Telegraf installation complete."
}

main
