#!/usr/bin/env bash
# shai installer / uninstaller
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zeddius1983/shell-assistant/main/install.sh)"
#   /bin/bash -c "$(curl -fsSL ...) " -- --uninstall
#
# Options (flags):
#   --uninstall           Remove shai and shell integration from RC files
#
# Options (env vars):
#   SHAI_NO_SHELL_INTEGRATION=1   Skip adding shell integration to RC file
#   SHAI_PURGE=1                  With --uninstall: also delete config and cache
#   SHAI_SOURCE=pypi|github       Force install source (default: pypi)

set -euo pipefail

PYPI_PACKAGE="shai"
GITHUB_PACKAGE="git+https://github.com/zeddius1983/shell-assistant.git"

# ---------- helpers ----------------------------------------------------------

bold()   { printf '\033[1m%s\033[0m' "$*"; }
green()  { printf '\033[32m%s\033[0m' "$*"; }
yellow() { printf '\033[33m%s\033[0m' "$*"; }
red()    { printf '\033[31m%s\033[0m' "$*"; }
dim()    { printf '\033[2m%s\033[0m' "$*"; }

step() { printf '\n%s %s\n' "$(bold '==>')" "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    %s\n' "$(yellow "Warning: $*")"; }
die()  { printf '\n%s %s\n\n' "$(red 'Error:')" "$*" >&2; exit 1; }

# Portable in-place sed: handles macOS (BSD sed) and Linux (GNU sed)
_sed_i() {
    if sed --version 2>/dev/null | grep -q GNU; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

# ---------- shell detection --------------------------------------------------

_detect_shell() {
    local shell_name
    shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        zsh)  echo "zsh" ;;
        bash) echo "bash" ;;
        *)    echo "" ;;
    esac
}

_rc_file() {
    case "$1" in
        zsh)  echo "${ZDOTDIR:-$HOME}/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
    esac
}

# ---------- uv ---------------------------------------------------------------

_ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        info "uv $(uv --version 2>/dev/null | awk '{print $2}') already installed"
        return
    fi

    step "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # uv installs to ~/.local/bin or ~/.cargo/bin; add both to PATH for this session
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

    command -v uv >/dev/null 2>&1 \
        || die "uv installation failed. Install manually: https://docs.astral.sh/uv/"
    info "$(green "uv installed")"
}

# ---------- clean up old non-uv installs -------------------------------------

_remove_old_installs() {
    local removed=0

    # pip / pip3 installs (system Python, Homebrew Python, etc.)
    for pip_cmd in pip3 pip; do
        if command -v "$pip_cmd" >/dev/null 2>&1; then
            if "$pip_cmd" show shai >/dev/null 2>&1; then
                info "Removing old pip install ($pip_cmd)..."
                "$pip_cmd" uninstall -y shai 2>/dev/null && removed=1 \
                    || warn "Could not remove pip install via $pip_cmd — may need sudo"
            fi
        fi
    done

    (( removed )) && info "$(green "Old pip install removed")" || true
}

# ---------- shai install / uninstall -----------------------------------------

_install_shai() {
    step "Installing shai..."

    _remove_old_installs

    local source="${SHAI_SOURCE:-pypi}"

    if [ "$source" = "github" ]; then
        uv tool install "$GITHUB_PACKAGE" --force --refresh
    else
        # Try PyPI first; fall back to GitHub if the package isn't published yet
        if uv tool install "$PYPI_PACKAGE" --force 2>/dev/null; then
            : # success
        else
            warn "PyPI install failed, falling back to GitHub..."
            command -v git >/dev/null 2>&1 \
                || die "git is required for GitHub install but was not found. Install git and retry."
            uv tool install "$GITHUB_PACKAGE" --force --refresh
        fi
    fi

    # uv tool bin directory is not always on PATH yet
    export PATH="$(uv tool dir 2>/dev/null | sed 's|/tools$|/bin|'):$HOME/.local/bin:$PATH"

    command -v shai >/dev/null 2>&1 \
        || die "shai binary not found after install. Try opening a new terminal."

    info "$(green "shai installed successfully")"
}

_uninstall_shai() {
    step "Uninstalling shai..."

    # uv tool uninstall
    if command -v uv >/dev/null 2>&1 && uv tool list 2>/dev/null | grep -q '^shai'; then
        uv tool uninstall shai \
            && info "$(green "Removed uv tool install")" \
            || warn "uv tool uninstall failed"
    else
        info "No uv tool install found"
    fi

    # Old pip / pip3 installs
    _remove_old_installs

    info "$(green "shai uninstalled")"
}

# ---------- shell integration ------------------------------------------------

_add_shell_integration() {
    local shell="$1"
    local rc="$2"

    # 'command shai' bypasses any alias (e.g. old 'alias shai=noglob _shai')
    # so the source line works correctly even after upgrades.
    local line="source \"\$(command shai --shell-path ${shell})\""
    local marker="shai --shell-path"

    if [ -f "$rc" ] && grep -qF "$marker" "$rc"; then
        info "Shell integration already present in $(bold "$rc") — skipping"
        return
    fi

    printf '\n# shai shell integration\n%s\n' "$line" >> "$rc"
    info "Added shell integration to $(bold "$rc")"
}

_remove_shell_integration() {
    local removed=0
    for rc in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
        [ -f "$rc" ] || continue
        if grep -qE 'shai --shell-path|# shai shell integration' "$rc"; then
            # Remove the marker comment and the source line (with or without 'command')
            _sed_i '/# shai shell integration/d' "$rc"
            _sed_i '/shai --shell-path/d' "$rc"
            info "Removed shell integration from $(bold "$rc")"
            removed=1
        fi
    done
    (( removed )) || info "No shell integration found in RC files"
}

# ---------- purge config / cache ---------------------------------------------

_purge_data() {
    step "Purging config and cache..."

    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/shai"
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/shai"
    local mac_cache="$HOME/Library/Caches/shai"

    for dir in "$config_dir" "$cache_dir" "$mac_cache"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir" && info "Removed $dir"
        fi
    done
}

# ---------- main -------------------------------------------------------------

main() {
    local mode="install"
    for arg in "$@"; do
        case "$arg" in
            --uninstall) mode="uninstall" ;;
            *) warn "Unknown option: $arg" ;;
        esac
    done

    printf '\n%s\n' "$(bold 'shai — Shell AI assistant')"
    printf '%s\n' "$(dim 'https://github.com/zeddius1983/shell-assistant')"

    if [ "$mode" = "uninstall" ]; then
        _uninstall_shai
        _remove_shell_integration
        if [ "${SHAI_PURGE:-0}" = "1" ]; then
            _purge_data
        else
            info "$(dim "Tip: set SHAI_PURGE=1 to also delete config and cache")"
        fi
        printf '\n%s\n\n' "$(green "$(bold '✓ shai uninstalled.')")"
        printf 'Reload your shell to complete removal:\n'
        printf '  %s\n\n' "$(bold 'exec $SHELL')"
        return
    fi

    # install mode
    _ensure_uv
    _install_shai

    if [ "${SHAI_NO_SHELL_INTEGRATION:-0}" = "1" ]; then
        warn "Skipping shell integration (SHAI_NO_SHELL_INTEGRATION=1)"
    else
        local shell rc
        shell="$(_detect_shell)"

        if [ -z "$shell" ]; then
            warn "Could not detect shell (SHELL='${SHELL:-}')."
            printf '\n  Add one of these lines to your shell RC file manually:\n\n'
            printf '    %s\n' "$(bold 'source "$(command shai --shell-path zsh)"')   # zsh"
            printf '    %s\n\n' "$(bold 'source "$(command shai --shell-path bash)"')  # bash"
        else
            rc="$(_rc_file "$shell")"
            step "Setting up shell integration ($shell → $rc)..."
            _add_shell_integration "$shell" "$rc"
        fi
    fi

    local shell rc_hint
    shell="$(_detect_shell)"
    rc_hint="${shell:+$(_rc_file "$shell")}"
    rc_hint="${rc_hint:-~/.zshrc or ~/.bashrc}"

    printf '\n%s\n\n' "$(green "$(bold '✓ Done!')")"
    printf 'Next steps:\n\n'
    printf '  1. Reload your shell:\n'
    printf '       %s\n\n' "$(bold "source $rc_hint")"
    printf '  2. Create your config and add an API key:\n'
    printf '       %s\n\n' "$(bold 'shai /config')"
    printf '  3. Try it:\n'
    printf '       %s\n\n' "$(bold 'shai help')"
    printf '%s\n\n' \
        "$(dim 'Tip: install glow for rendered markdown output: brew install glow')"
}

main "$@"
