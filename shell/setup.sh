#!/usr/bin/env bash
# Shai Toolbox — cross-platform ZSH environment installer
#
# Usage:
#   Interactive (pick what to install):
#     ./shell/setup.sh
#
#   Silent — install everything:
#     ./shell/setup.sh --all
#     SETUP_SILENT=1 bash ./shell/setup.sh
#
#   Via curl (silent):
#     curl -fsSL https://raw.githubusercontent.com/zeddius1983/shell-assistant/main/shell/setup.sh | bash -s -- --all

set -euo pipefail

# ---------------------------------------------------------------------------
# Colours & output helpers
# ---------------------------------------------------------------------------

bold()    { printf '\033[1m%s\033[0m' "$*"; }
green()   { printf '\033[32m%s\033[0m' "$*"; }
yellow()  { printf '\033[33m%s\033[0m' "$*"; }
red()     { printf '\033[31m%s\033[0m' "$*"; }
cyan()    { printf '\033[36m%s\033[0m' "$*"; }
dim()     { printf '\033[2m%s\033[0m' "$*"; }

step()  { printf '\n%s %s\n' "$(bold '==>')" "$*"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s\n' "$(green "✓ $*")"; }
warn()  { printf '    %s\n' "$(yellow "Warning: $*")"; }
die()   { printf '\n%s %s\n\n' "$(red 'Error:')" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------

OS=""
case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then
      OS="linux"
    else
      die "Only Debian/Ubuntu Linux is supported. Install packages manually."
    fi
    ;;
  *) die "Unsupported OS: $(uname -s)" ;;
esac

# ---------------------------------------------------------------------------
# Package manager helpers
# ---------------------------------------------------------------------------

_ensure_brew() {
  if command -v brew >/dev/null 2>&1; then return; fi
  step "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for this session
  if [ -x "/opt/homebrew/bin/brew" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x "/usr/local/bin/brew" ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

_brew() { brew install "$@" 2>/dev/null || brew upgrade "$@" 2>/dev/null || true; }

_apt_update_done=0
_apt() {
  if [ "$_apt_update_done" -eq 0 ]; then
    sudo apt-get update -q
    _apt_update_done=1
  fi
  sudo apt-get install -y --no-install-recommends "$@"
}

_add_apt_repo() {
  local name="$1" key_url="$2" repo_line="$3" list_file="$4"
  if [ -f "$list_file" ]; then return; fi
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL "$key_url" | gpg --dearmor | sudo tee /etc/apt/keyrings/"${name}".gpg >/dev/null
  echo "$repo_line" | sudo tee "$list_file" >/dev/null
  _apt_update_done=0   # force re-update after adding repo
}

# ---------------------------------------------------------------------------
# .zshrc idempotent patching
# ---------------------------------------------------------------------------

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

_zshrc_has() { grep -qF "zsh-toolbox:$1" "$ZSHRC" 2>/dev/null; }

_zshrc_add() {
  local key="$1"; shift
  if _zshrc_has "$key"; then
    info "$(dim "~/.zshrc[$key] already present — skipping")"
    return
  fi
  {
    printf '\n# -- shai-toolbox: %s --\n' "$key"
    printf '%s\n' "$@"
    printf '# -- end shai-toolbox: %s --\n' "$key"
  } >> "$ZSHRC"
  info "Added $key to ~/.zshrc"
}

# ---------------------------------------------------------------------------
# Install functions — one per component
# ---------------------------------------------------------------------------

install_shai() {
  step "Installing shai..."
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  fi
  uv tool install "git+https://github.com/zeddius1983/shell-assistant.git" --force --refresh
  export PATH="$(uv tool dir 2>/dev/null | sed 's|/tools$|/bin|'):$HOME/.local/bin:$PATH"
  _zshrc_add "shai" 'source "$(shai --shell-path zsh)"'
  ok "shai installed"
}

install_starship() {
  step "Installing starship..."
  case "$OS" in
    mac)   _ensure_brew; _brew starship ;;
    linux) curl -sS https://starship.rs/install.sh | sh -s -- --yes ;;
  esac
  _zshrc_add "starship" 'eval "$(starship init zsh)"'
  # Copy starship.toml
  local toml_src
  toml_src="$(cd "$(dirname "$0")" && pwd)/starship.toml"
  if [ -f "$toml_src" ]; then
    mkdir -p "$HOME/.config"
    cp "$toml_src" "$HOME/.config/starship.toml"
    info "Copied starship.toml → ~/.config/starship.toml"
  else
    warn "starship.toml not found next to setup.sh — skipping config copy"
  fi
  ok "starship installed"
}

install_eza() {
  step "Installing eza..."
  case "$OS" in
    mac) _ensure_brew; _brew eza ;;
    linux)
      _add_apt_repo "gierens" \
        "https://raw.githubusercontent.com/eza-community/eza/main/deb.asc" \
        "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
        "/etc/apt/sources.list.d/gierens.list"
      _apt eza
      ;;
  esac
  _zshrc_add "eza" \
    "alias ls='eza --icons --group-directories-first'" \
    "alias ll='eza --icons --group-directories-first -l --git'" \
    "alias la='eza --icons --group-directories-first -la --git'" \
    "alias lt='eza --icons --tree --level=2'" \
    "alias lta='eza --icons --tree --level=2 -a'"
  ok "eza installed"
}

install_bat() {
  step "Installing bat..."
  case "$OS" in
    mac) _ensure_brew; _brew bat ;;
    linux)
      _apt bat
      # Ubuntu names it batcat; create symlink
      if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
        sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
      fi
      ;;
  esac
  _zshrc_add "bat" \
    "alias cat='bat'" \
    "alias less='bat'"
  ok "bat installed"
}

install_zoxide() {
  step "Installing zoxide..."
  case "$OS" in
    mac) _ensure_brew; _brew zoxide ;;
    linux) _apt zoxide ;;
  esac
  _zshrc_add "zoxide" 'eval "$(zoxide init zsh)"'
  ok "zoxide installed"
}

install_fzf() {
  step "Installing fzf..."
  case "$OS" in
    mac) _ensure_brew; _brew fzf ;;
    linux) _apt fzf ;;
  esac
  # Fetch key-binding scripts (Ubuntu strips /usr/share/doc)
  curl -sSLo "$HOME/.fzf-key-bindings.zsh" \
    https://raw.githubusercontent.com/junegunn/fzf/master/shell/key-bindings.zsh
  curl -sSLo "$HOME/.fzf-completion.zsh" \
    https://raw.githubusercontent.com/junegunn/fzf/master/shell/completion.zsh
  _zshrc_add "fzf" \
    'source "$HOME/.fzf-key-bindings.zsh"' \
    'source "$HOME/.fzf-completion.zsh"'
  ok "fzf installed"
}

install_atuin() {
  step "Installing atuin..."
  case "$OS" in
    mac) _ensure_brew; _brew atuin ;;
    linux) bash -c "$(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)" ;;
  esac
  _zshrc_add "atuin" 'eval "$(atuin init zsh)"'
  ok "atuin installed"
}

install_direnv() {
  step "Installing direnv..."
  case "$OS" in
    mac) _ensure_brew; _brew direnv ;;
    linux) _apt direnv ;;
  esac
  _zshrc_add "direnv" 'eval "$(direnv hook zsh)"'
  ok "direnv installed"
}

install_glow() {
  step "Installing glow..."
  case "$OS" in
    mac) _ensure_brew; _brew glow ;;
    linux)
      _add_apt_repo "charm" \
        "https://repo.charm.sh/apt/gpg.key" \
        "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
        "/etc/apt/sources.list.d/charm.list"
      _apt glow
      ;;
  esac
  ok "glow installed"
}

install_ripgrep() {
  step "Installing ripgrep (rg)..."
  case "$OS" in
    mac) _ensure_brew; _brew ripgrep ;;
    linux) _apt ripgrep ;;
  esac
  ok "ripgrep installed"
}

install_fd() {
  step "Installing fd..."
  case "$OS" in
    mac) _ensure_brew; _brew fd ;;
    linux)
      _apt fd-find
      if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
        sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd
      fi
      ;;
  esac
  ok "fd installed"
}

install_vim() {
  step "Installing vim..."
  case "$OS" in
    mac) _ensure_brew; _brew vim ;;
    linux) _apt vim ;;
  esac
  # Basic vim config with syntax highlighting
  {
    printf 'syntax on\n'
    printf 'set background=dark\n'
    printf 'set number\n'
  } >> "$HOME/.vimrc" 2>/dev/null || true
  _zshrc_add "vim" "alias vi='vim'"
  ok "vim installed"
}

install_zsh_plugins() {
  step "Installing ZSH plugins (autosuggestions + syntax highlighting)..."
  case "$OS" in
    mac)
      _ensure_brew
      _brew zsh-autosuggestions zsh-syntax-highlighting
      local brew_prefix
      brew_prefix="$(brew --prefix)"
      _zshrc_add "zsh-plugins" \
        "source ${brew_prefix}/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
        "source ${brew_prefix}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
      ;;
    linux)
      _apt zsh-autosuggestions zsh-syntax-highlighting
      _zshrc_add "zsh-plugins" \
        "source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh" \
        "source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
      ;;
  esac
  ok "ZSH plugins installed"
}

# ---------------------------------------------------------------------------
# Interactive menu (pure POSIX shell — no whiptail/dialog needed)
# ---------------------------------------------------------------------------

# Menu entries: "key|label|description|default_selected"
MENU_ENTRIES=(
  "starship|starship|Fast, customizable prompt|1"
  "eza|eza|Modern ls with icons and git info|1"
  "bat|bat|Syntax-highlighted cat and less replacement|1"
  "zoxide|zoxide|Smarter cd that learns your paths|1"
  "fzf|fzf|Fuzzy finder for files, history, and more|1"
  "atuin|atuin|Shell history with search and sync|1"
  "direnv|direnv|Auto-load project .env files|1"
  "glow|glow|Render markdown in the terminal|1"
  "ripgrep|ripgrep (rg)|Blazing fast grep alternative|1"
  "fd|fd|Fast and user-friendly find alternative|1"
  "vim|vim|Vi editor with syntax highlighting|1"
  "zsh_plugins|ZSH plugins|Autosuggestions + syntax highlighting|1"
)

_show_menu() {
  local n=${#MENU_ENTRIES[@]}
  # selected_N variables hold 0/1 for each entry
  local i=0
  while [ $i -lt $n ]; do
    local default
    default="$(echo "${MENU_ENTRIES[$i]}" | cut -d'|' -f4)"
    eval "selected_$i=$default"
    i=$((i + 1))
  done

  local cursor=0

  # Hide cursor, save terminal settings
  tput civis 2>/dev/null || true
  local old_stty
  old_stty="$(stty -g 2>/dev/null || echo '')"
  stty raw -echo 2>/dev/null || true

  _menu_render() {
    # Move cursor to top of menu area
    printf '\033[%dA' "$((n + 5))" 2>/dev/null || true
    printf '\033[J'   # clear to end of screen

    printf '\n  %s\n' "$(bold 'Shai Toolbox Setup')"
    printf '  %s\n\n' "$(dim '──────────────────────────────────────')"
    printf '  %s  %s\n' "$(cyan '[*]')" "$(bold 'shai')  — $(dim 'AI shell assistant (always installed)')"
    local j=0
    while [ $j -lt $n ]; do
      local key label desc sel
      key="$(echo "${MENU_ENTRIES[$j]}" | cut -d'|' -f1)"
      label="$(echo "${MENU_ENTRIES[$j]}" | cut -d'|' -f2)"
      desc="$(echo "${MENU_ENTRIES[$j]}" | cut -d'|' -f3)"
      eval "sel=\$selected_$j"
      local check
      if [ "$sel" -eq 1 ]; then
        check="$(green '[x]')"
      else
        check='[ ]'
      fi
      if [ "$j" -eq "$cursor" ]; then
        printf '  %s %s  %s  %s\n' "$check" "$(bold "▶ $label")" "$(dim '—')" "$(dim "$desc")"
      else
        printf '  %s %s  %s  %s\n' "$check" "$label" "$(dim '—')" "$(dim "$desc")"
      fi
      j=$((j + 1))
    done
    printf '\n  %s\n' "$(dim 'SPACE toggle · ENTER confirm · a select all · n deselect all · q quit')"
  }

  # Initial render — print blank lines to reserve space
  printf '\n'; printf '%.0s\n' $(seq 1 $((n + 5)))
  _menu_render

  while true; do
    # Read one char (handle escape sequences for arrow keys)
    local char
    IFS= read -r -s -n1 char || true

    if [ "$char" = $'\x1b' ]; then
      IFS= read -r -s -n1 -t 0.1 char2 || true
      if [ "$char2" = '[' ]; then
        IFS= read -r -s -n1 -t 0.1 char3 || true
        case "$char3" in
          A) [ $cursor -gt 0 ] && cursor=$((cursor - 1)) ;;       # up
          B) [ $cursor -lt $((n - 1)) ] && cursor=$((cursor + 1)) ;; # down
        esac
      fi
    elif [ "$char" = ' ' ]; then
      local cur_sel
      eval "cur_sel=\$selected_$cursor"
      eval "selected_$cursor=$(( 1 - cur_sel ))"
    elif [ "$char" = 'a' ]; then
      local k=0; while [ $k -lt $n ]; do eval "selected_$k=1"; k=$((k+1)); done
    elif [ "$char" = 'n' ]; then
      local k=0; while [ $k -lt $n ]; do eval "selected_$k=0"; k=$((k+1)); done
    elif [ "$char" = $'\r' ] || [ "$char" = $'\n' ] || [ "$char" = '' ]; then
      break
    elif [ "$char" = 'q' ]; then
      stty "$old_stty" 2>/dev/null || true
      tput cnorm 2>/dev/null || true
      printf '\n\nAborted.\n'
      exit 0
    fi
    _menu_render
  done

  stty "$old_stty" 2>/dev/null || true
  tput cnorm 2>/dev/null || true
  printf '\n'

  # Emit selected keys to a temp file (read back in main)
  local k=0
  while [ $k -lt $n ]; do
    local sel
    eval "sel=\$selected_$k"
    if [ "$sel" -eq 1 ]; then
      echo "$(echo "${MENU_ENTRIES[$k]}" | cut -d'|' -f1)"
    fi
    k=$((k + 1))
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  printf '\n%s\n' "$(bold '  Shai Toolbox Setup')"
  printf '%s\n\n' "$(dim '  https://github.com/zeddius1983/shell-assistant')"

  local silent=0
  for arg in "$@"; do
    case "$arg" in
      --all|-a) silent=1 ;;
    esac
  done
  [ "${SETUP_SILENT:-0}" = "1" ] && silent=1

  # Touch ~/.zshrc if not present
  touch "$ZSHRC"

  local to_install
  to_install=""

  if [ "$silent" -eq 1 ]; then
    info "$(yellow "Silent mode: installing all components")"
    to_install="starship eza bat zoxide fzf atuin direnv glow ripgrep fd vim zsh_plugins"
  else
    # Check we have a real TTY for the interactive menu
    if [ ! -t 0 ] || [ ! -t 1 ]; then
      warn "No TTY detected (running via pipe?). Switching to --all mode."
      to_install="starship eza bat zoxide fzf atuin direnv glow ripgrep fd vim zsh_plugins"
    else
      local _menu_tmp
      _menu_tmp="$(mktemp)"
      _show_menu > "$_menu_tmp"
      to_install="$(cat "$_menu_tmp")"
      rm -f "$_menu_tmp"
    fi
  fi

  # shai is always installed
  install_shai

  for component in $to_install; do
    case "$component" in
      starship)    install_starship ;;
      eza)         install_eza ;;
      bat)         install_bat ;;
      zoxide)      install_zoxide ;;
      fzf)         install_fzf ;;
      atuin)       install_atuin ;;
      direnv)      install_direnv ;;
      glow)        install_glow ;;
      ripgrep)     install_ripgrep ;;
      fd)          install_fd ;;
      vim)         install_vim ;;
      zsh_plugins) install_zsh_plugins ;;
    esac
  done

  printf '\n%s\n\n' "$(green "$(bold '✓ All done!')")"
  printf 'Reload your shell to apply changes:\n'
  printf '  %s\n\n' "$(bold "source $ZSHRC")"
}

main "$@"
