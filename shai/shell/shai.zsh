# shai zsh integration
# Source this file in your ~/.zshrc:
#   source "$(shai --shell-path zsh)"
# or manually:
#   source /path/to/shai/shell/shai.zsh

# Only load in zsh
[ -n "$ZSH_VERSION" ] || return 0

_shai_context_file="${XDG_CACHE_HOME:-$HOME/.cache}/shai/context"

_shai_save_context() {
    local exit_code=$?
    mkdir -p "$(dirname "$_shai_context_file")"

    if [ -n "$TMUX" ]; then
        tmux capture-pane -p -S -200 2>/dev/null > "$_shai_context_file"
    else
        local last_cmd
        last_cmd=$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//')
        {
            echo "$ ${last_cmd}"
            if [ "$exit_code" -ne 0 ]; then
                echo "[exited with code $exit_code]"
            fi
        } > "$_shai_context_file"
    fi
    return $exit_code
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _shai_save_context

# ──────────────────────────────────────────────────────────────────────────────
# shai smart autocomplete  (experimental, opt-in)
#
# Activate by setting SHAI_AUTOCOMPLETE=1 before sourcing this file.
# Configuration via environment variables:
#   SHAI_AC_KEY          Key binding (default: ^@ = Ctrl+Space)
#   SHAI_AC_COUNT        Number of suggestions (default: 3, or from config)
#   SHAI_AC_DEBOUNCE     Set to 1 to enable debounce mode (requires zsh 5.8+)
#   SHAI_AC_DEBOUNCE_MS  Debounce delay in ms (default: 1500)
#
# UX:
#   First press  → fetch suggestions; show #1 as inline ghost text (→ accepts)
#   Second press → open fzf picker with all suggestions
#   Typing       → clears ghost text
# ──────────────────────────────────────────────────────────────────────────────
if [[ -n "$SHAI_AUTOCOMPLETE" ]] && command -v shai >/dev/null 2>&1; then

  typeset -g _shai_ac_suggestions=()
  typeset -g _shai_ac_query=""
  typeset -g _shai_ac_active=0   # 1 while ghost text is ours

  # ── main widget ─────────────────────────────────────────────────────────────
  _shai_ac_widget() {
    local query="$BUFFER"
    [[ -z "$query" ]] && return

    # Second press on the same buffer → open fzf picker
    if (( _shai_ac_active )) && [[ "$query" == "$_shai_ac_query" ]]; then
      _shai_ac_fzf
      return
    fi

    # Clear any previous ghost text we own
    if (( _shai_ac_active )); then
      POSTDISPLAY=""
      _shai_ac_active=0
      _shai_ac_suggestions=()
    fi

    # Fetch suggestions — stderr suppressed so errors never corrupt the prompt
    local raw
    raw=$(shai complete --count "${SHAI_AC_COUNT:-3}" -- "$query" 2>/dev/null)
    [[ -z "$raw" ]] && return

    _shai_ac_suggestions=("${(@f)raw}")
    _shai_ac_query="$query"
    _shai_ac_active=1

    # Display the first suggestion as ghost text (the suffix after what's typed)
    local first="${_shai_ac_suggestions[1]}"
    if [[ "$first" == "$query"* ]]; then
      POSTDISPLAY="${first#"$query"}"
    else
      POSTDISPLAY=""
    fi

    zle -R
  }

  # ── accept ghost text ────────────────────────────────────────────────────────
  _shai_ac_accept() {
    BUFFER="${BUFFER}${POSTDISPLAY}"
    CURSOR=${#BUFFER}
    POSTDISPLAY=""
    _shai_ac_active=0
    _shai_ac_suggestions=()
    _shai_ac_query=""
  }

  # → accepts ghost text when cursor is at the end; otherwise moves normally
  _shai_ac_forward_char() {
    if (( _shai_ac_active )) && [[ -n "$POSTDISPLAY" ]] && (( CURSOR == ${#BUFFER} )); then
      _shai_ac_accept
    else
      zle forward-char
    fi
  }

  # End / Ctrl+E accepts ghost text unconditionally
  _shai_ac_end_of_line() {
    if (( _shai_ac_active )) && [[ -n "$POSTDISPLAY" ]]; then
      _shai_ac_accept
    else
      zle end-of-line
    fi
  }

  # ── fzf picker ───────────────────────────────────────────────────────────────
  _shai_ac_fzf() {
    [[ ${#_shai_ac_suggestions[@]} -eq 0 ]] && return

    local selected
    selected=$(printf '%s\n' "${_shai_ac_suggestions[@]}" \
      | fzf --height=~40% --reverse --no-sort \
            --prompt="shai ❯ " \
            --header="↵ accept  ESC cancel" \
            2>/dev/tty)

    POSTDISPLAY=""
    _shai_ac_active=0
    _shai_ac_suggestions=()
    _shai_ac_query=""

    if [[ -n "$selected" ]]; then
      BUFFER="$selected"
      CURSOR=${#BUFFER}
    fi
    zle reset-prompt
  }

  # ── clear ghost text when the user types (buffer changes) ───────────────────
  _shai_ac_pre_redraw() {
    if (( _shai_ac_active )) && [[ "$BUFFER" != "$_shai_ac_query" ]]; then
      POSTDISPLAY=""
      _shai_ac_active=0
      _shai_ac_suggestions=()
      _shai_ac_query=""
    fi

    # Debounce mode: schedule autocomplete after a pause in typing (zsh 5.8+)
    if [[ -n "$SHAI_AC_DEBOUNCE" ]] && (( ${#BUFFER} > 0 )) && ! (( _shai_ac_active )); then
      zle -t "${SHAI_AC_DEBOUNCE_MS:-1500}" _shai_ac_widget 2>/dev/null || true
    fi
  }

  # ── register widgets ─────────────────────────────────────────────────────────
  zle -N _shai_ac_widget
  zle -N _shai_ac_fzf
  zle -N _shai_ac_forward_char
  zle -N _shai_ac_end_of_line

  # Use add-zle-hook-widget so we coexist with zsh-autosuggestions and others
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget line-pre-redraw _shai_ac_pre_redraw

  # ── key bindings ─────────────────────────────────────────────────────────────
  bindkey "${SHAI_AC_KEY:-^@}" _shai_ac_widget   # Ctrl+Space (default)

  # Override → and End to accept ghost text; fall through otherwise
  bindkey "^[[C"   _shai_ac_forward_char          # → xterm / kitty
  bindkey "^[OC"   _shai_ac_forward_char          # → vt100 / tmux
  bindkey "^E"     _shai_ac_end_of_line           # Ctrl+E
  bindkey "^[[F"   _shai_ac_end_of_line           # End (xterm)
  bindkey "^[OF"   _shai_ac_end_of_line           # End (vt100)

fi
