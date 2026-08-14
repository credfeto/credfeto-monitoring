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

install_ubuntu() {
    info "Installing Telegraf on Ubuntu/Debian..."
    info "Adding InfluxData apt repository..."

    # The old install left this file behind; a repository still configured to
    # trust it fails apt-get update with NO_PUBKEY once InfluxData rotates keys.
    # Removed unconditionally (not just when telegraf is missing) so a host that
    # already has telegraf installed is repaired too, rather than left with a
    # sources entry pointing at a keyring file that no longer exists.
    if [ -f /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg ]; then
        sudo rm -f /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg
    fi

    # Verified directly against https://repos.influxdata.com/influxdata-archive.key
    # with `gpg --show-keys --with-colons`; this is the primary key fingerprint,
    # which stays constant across InfluxData's subkey rotations (see issue #22).
    influxdata_key_fingerprint="24C975CBA61A024EE1B631787C3D57159FC2F927"
    keyring_path="/etc/apt/keyrings/influxdata-archive.gpg"
    sources_list="/etc/apt/sources.list.d/influxdata.list"
    sources_list_line="deb [arch=$(dpkg --print-architecture) signed-by=${keyring_path}] https://repos.influxdata.com/ubuntu stable main"
    work_dir=$(mktemp -d)
    trap 'rm -rf "${work_dir}"' EXIT
    export GNUPGHOME="${work_dir}/gnupg"
    mkdir -m 0700 "${GNUPGHOME}"

    # Skip the network fetch when the installed keyring is already the verified
    # key, so re-running this script on an already-repaired host is a no-op here.
    installed_fingerprint=$(key_fingerprint "${keyring_path}")
    if [ "${installed_fingerprint}" != "${influxdata_key_fingerprint}" ]; then
        curl -fsSL https://repos.influxdata.com/influxdata-archive.key -o "${work_dir}/key.asc"

        actual_fingerprint=$(key_fingerprint "${work_dir}/key.asc")
        if [ "${actual_fingerprint}" != "${influxdata_key_fingerprint}" ]; then
            die "InfluxData signing key fingerprint mismatch: expected ${influxdata_key_fingerprint}, got ${actual_fingerprint:-<none>}"
        fi

        gpg --yes --dearmor -o "${work_dir}/key.gpg" "${work_dir}/key.asc"

        sudo install -d -m 0755 /etc/apt/keyrings
        sudo install -m 0644 "${work_dir}/key.gpg" "${keyring_path}"
    fi

    if [ "$(cat "${sources_list}" 2>/dev/null)" != "${sources_list_line}" ]; then
        echo "${sources_list_line}" | sudo tee "${sources_list}" > /dev/null
    fi

    if ! dpkg -l telegraf 2>/dev/null | grep -q '^ii'; then
        sudo apt-get update -qq
        sudo apt-get install -y telegraf
    else
        info "Telegraf already installed, skipping package install."
    fi
}

install_arch() {
    info "Installing Telegraf on Arch Linux..."

    if ! pacman -Qi telegraf > /dev/null 2>&1; then
        sudo pacman -S --noconfirm telegraf
    else
        info "Telegraf already installed, skipping package install."
    fi
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

main() {
    detect_and_install
    add_telegraf_to_docker_group
    success "Telegraf installation complete."
}

main
