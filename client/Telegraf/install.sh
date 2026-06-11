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

install_ubuntu() {
    info "Installing Telegraf on Ubuntu/Debian..."

    if ! dpkg -l telegraf 2>/dev/null | grep -q '^ii'; then
        info "Adding InfluxData apt repository..."
        curl -fsSL https://repos.influxdata.com/influxdata-archive_compat.key \
            | gpg --dearmor \
            | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null
        echo "deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/ubuntu stable main" \
            | sudo tee /etc/apt/sources.list.d/influxdata.list > /dev/null
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
