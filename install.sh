#!/usr/bin/env bash
# shai installer
#
# Usage:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zeddius1983/shell-assistant/main/install.sh)"
#
# Options (set as env vars before running):
#   SHAI_NO_SHELL_INTEGRATION=1   Skip adding shell integration to RC file
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

# ---------- shai install -----------------------------------------------------

_install_shai() {
    step "Installing shai..."

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

# ---------- shell integration ------------------------------------------------

_add_shell_integration() {
    local shell="$1"
    local rc="$2"

    local line="_shai_p=\"\$(shai --shell-path ${shell} 2>/dev/null | xargs)\" && [ -n \"\$_shai_p\" ] && source \"\$_shai_p\""
    local marker="shai --shell-path"

    if [ -f "$rc" ] && grep -qF "$marker" "$rc"; then
        info "Shell integration already present in $(bold "$rc") — skipping"
        return
    fi

    printf '\n# shai shell integration\n%s\n' "$line" >> "$rc"
    info "Added shell integration to $(bold "$rc")"
}

# ---------- main -------------------------------------------------------------

main() {
    printf '\n%s\n' "$(bold 'shai — Shell AI assistant installer')"
    printf '%s\n' "$(dim 'https://github.com/zeddius1983/shell-assistant')"

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
            printf '    %s\n' "$(bold 'source "$(shai --shell-path zsh)"')   # zsh"
            printf '    %s\n\n' "$(bold 'source "$(shai --shell-path bash)"')  # bash"
        else
            rc="$(_rc_file "$shell")"
            step "Setting up shell integration ($shell → $rc)..."
            _add_shell_integration "$shell" "$rc"
        fi
    fi

    # Determine the right RC file for the reload hint
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
