#!/usr/bin/env bash

# nerd font
# ripgrep
# fzf
# fd
# tree-sitter-cli
# oh-my-pi
# git
# curl
# unzip
# gzip
# tar
# make

set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"

if [ ! -r /etc/os-release ]; then
    printf 'Cannot detect the operating system. /etc/os-release is missing.\n' >&2
    exit 1
fi

. /etc/os-release

case "${ID:-}" in
    ubuntu)
        package_manager=apt
        ;;
    manjaro|arch|archlinux)
        package_manager=pacman
        ;;
    *)
        printf 'Unsupported operating system: %s. Supported systems: Ubuntu, Manjaro, Arch Linux.\n' "${ID:-unknown}" >&2
        exit 1
        ;;
esac

has_command() {
    command -v "$1" >/dev/null 2>&1
}

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif has_command sudo; then
        sudo "$@"
    else
        printf 'sudo is required to install system packages.\n' >&2
        return 1
    fi
}

install_system_packages() {
    if [ "$#" -eq 0 ]; then
        return 0
    fi

    case "$package_manager" in
        apt)
            run_as_root apt-get install -y "$@"
            ;;
        pacman)
            run_as_root pacman -S --needed --noconfirm "$@"
            ;;
    esac
}

ensure_system_command() {
    local command_name="$1"
    local apt_package="$2"
    local pacman_package="$3"

    if has_command "$command_name"; then
        return 0
    fi

    if [ "$package_manager" = apt ]; then
        install_system_packages "$apt_package"
    else
        install_system_packages "$pacman_package"
    fi

    if ! has_command "$command_name"; then
        printf 'Unable to install required command: %s\n' "$command_name" >&2
        return 1
    fi
}

ensure_fd() {
    if has_command fd || has_command fdfind; then
        return 0
    fi

    if [ "$package_manager" = apt ]; then
        install_system_packages fd-find
    else
        install_system_packages fd
    fi

    if has_command fd; then
        return 0
    fi

    if has_command fdfind; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        return 0
    fi

    printf 'Unable to install required command: fd\n' >&2
    return 1
}

font_installed() {
    if has_command fc-list; then
        fc-list : family 2>/dev/null | grep -Fqi 'JetBrainsMono Nerd Font'
        return $?
    fi

    find "$HOME/.local/share/fonts" -type f \( -iname 'JetBrainsMonoNerdFont*.ttf' -o -iname 'JetBrainsMonoNerdFont*.otf' \) -print -quit 2>/dev/null | grep -q .
}

install_nerd_font() {
    local tmp_dir
    local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"

    tmp_dir=$(mktemp -d)
    curl -fsSL 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip' -o "$tmp_dir/JetBrainsMono.zip"
    unzip -q "$tmp_dir/JetBrainsMono.zip" -d "$tmp_dir/fonts"
    mkdir -p "$font_dir"
    find "$tmp_dir/fonts" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -exec cp -f {} "$font_dir/" \;
    rm -rf "$tmp_dir"

    if has_command fc-cache; then
        fc-cache -f "$font_dir"
    fi
}

ensure_node_runtime() {
    if has_command bun || has_command npm; then
        return 0
    fi

    install_system_packages nodejs npm

    if ! has_command bun && ! has_command npm; then
        printf 'Unable to install a JavaScript package manager.\n' >&2
        return 1
    fi
}

install_node_package() {
    local package_name="$1"
    local command_name="$2"

    if has_command "$command_name"; then
        return 0
    fi

    ensure_node_runtime
    if has_command bun; then
        bun install --global "$package_name"
    else
        npm install --global --prefix "$HOME/.local" "$package_name"
    fi

    if ! has_command "$command_name"; then
        printf 'Unable to install required command: %s\n' "$command_name" >&2
        return 1
    fi
}

ensure_system_command rg ripgrep ripgrep
ensure_system_command fzf fzf fzf
ensure_fd
ensure_system_command git git git
ensure_system_command curl curl curl
ensure_system_command unzip unzip unzip
ensure_system_command gzip gzip gzip
ensure_system_command tar tar tar
ensure_system_command make make make

if ! font_installed; then
    ensure_system_command fc-list fontconfig fontconfig
    if ! font_installed; then
        install_nerd_font
    fi
fi

install_node_package tree-sitter-cli tree-sitter

if ! has_command omp; then
    curl -fsSL 'https://omp.sh/install' | sh
fi

if ! has_command omp; then
    printf 'Unable to install required command: omp\n' >&2
    exit 1
fi

printf 'All Neovim requirements are installed.\n'
