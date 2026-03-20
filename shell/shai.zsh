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

    local last_cmd
    last_cmd=$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//')

    # Don't overwrite context when the last command was shai itself —
    # keep the previous command's context so 'shai help' sees the real output.
    case "$last_cmd" in
        shai*) return $exit_code ;;
    esac

    if [ -n "$TMUX" ]; then
        tmux capture-pane -p -S -200 2>/dev/null > "$_shai_context_file"
    else
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
#   SHAI_AC_DEBOUNCE     Set to 1 to enable debounce mode
#   SHAI_AC_DEBOUNCE_MS  Debounce delay in ms (default: 1500)
#
# UX:
#   First press  → fetch suggestions async; show ⟳ then ghost text (→ accepts)
#   Second press → open fzf picker with all suggestions
#   Typing       → clears ghost text / cancels in-flight fetch
# ──────────────────────────────────────────────────────────────────────────────
if [[ -n "$SHAI_AUTOCOMPLETE" ]] && command -v shai >/dev/null 2>&1; then

  typeset -g  _shai_ac_suggestions=()
  typeset -g  _shai_ac_query=""
  typeset -gi _shai_ac_active=0        # 1 when POSTDISPLAY is ours
  typeset -gi _shai_ac_fd=-1           # fd for in-flight fetch
  typeset -gi _shai_ac_debounce_fd=-1  # fd for debounce sleep

  # ── async response handler ───────────────────────────────────────────────────
  _shai_ac_handle_response() {
    local fd=$1 raw
    raw=$(cat <&$fd 2>/dev/null)
    zle -F $fd 2>/dev/null
    exec {fd}<&-
    _shai_ac_fd=-1

    # Discard if the user changed the buffer while we were fetching
    if [[ "$BUFFER" != "$_shai_ac_query" ]]; then
      POSTDISPLAY=""
      _shai_ac_active=0
      zle -R
      return
    fi

    POSTDISPLAY=""
    _shai_ac_suggestions=()

    if [[ -n "$raw" ]]; then
      _shai_ac_suggestions=("${(@f)raw}")
      local first="${_shai_ac_suggestions[1]}"
      if [[ "$first" == "$_shai_ac_query"* ]]; then
        POSTDISPLAY="${first#"$_shai_ac_query"}"
      fi
    fi

    # Keep _shai_ac_active=1 so forward-char / second press still work
    zle -R
  }

  # ── main widget ─────────────────────────────────────────────────────────────
  _shai_ac_widget() {
    local query="$BUFFER"
    [[ -z "$query" ]] && return

    # Second press on same query with results ready → open fzf
    if (( _shai_ac_active )) && [[ "$query" == "$_shai_ac_query" ]] \
        && (( ${#_shai_ac_suggestions[@]} > 0 )); then
      _shai_ac_fzf
      return
    fi

    # Cancel any in-flight fetch
    if (( _shai_ac_fd >= 0 )); then
      zle -F $_shai_ac_fd 2>/dev/null
      exec {_shai_ac_fd}<&-
      _shai_ac_fd=-1
    fi

    # Reset state and show thinking indicator while fetch runs
    _shai_ac_active=1
    _shai_ac_suggestions=()
    _shai_ac_query="$query"
    POSTDISPLAY=" ⟳"
    zle -R

    # Launch async fetch — ZLE stays responsive while this runs in the background
    exec {_shai_ac_fd}< <(shai complete --count "${SHAI_AC_COUNT:-3}" -- "$query" 2>/dev/null)
    zle -F $_shai_ac_fd _shai_ac_handle_response
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

  _shai_ac_forward_char() {
    if (( _shai_ac_active )) && [[ -n "$POSTDISPLAY" ]] && (( CURSOR == ${#BUFFER} )); then
      _shai_ac_accept
    else
      zle forward-char
    fi
  }

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

  # ── pre-redraw: clear state and manage debounce on every keypress ────────────
  _shai_ac_pre_redraw() {
    # Buffer changed — clear our ghost text / thinking indicator
    if (( _shai_ac_active )) && [[ "$BUFFER" != "$_shai_ac_query" ]]; then
      POSTDISPLAY=""
      _shai_ac_active=0
      _shai_ac_suggestions=()
      _shai_ac_query=""
    fi

    # Buffer changed while fetch was in-flight — cancel it
    if (( _shai_ac_fd >= 0 )) && [[ "$BUFFER" != "$_shai_ac_query" ]]; then
      zle -F $_shai_ac_fd 2>/dev/null
      exec {_shai_ac_fd}<&-
      _shai_ac_fd=-1
    fi

    # Debounce: cancel previous sleep, start a fresh one on every keypress.
    # When the user pauses, the sleep finishes and fires _shai_ac_debounce_done.
    if [[ -n "$SHAI_AC_DEBOUNCE" ]]; then
      if (( _shai_ac_debounce_fd >= 0 )); then
        zle -F $_shai_ac_debounce_fd 2>/dev/null
        exec {_shai_ac_debounce_fd}<&-
        _shai_ac_debounce_fd=-1
      fi
      if (( ${#BUFFER} > 0 )) && ! (( _shai_ac_active )) && (( _shai_ac_fd < 0 )); then
        local delay_s snapshot="$BUFFER"
        printf -v delay_s '%.3f' "$(( ${SHAI_AC_DEBOUNCE_MS:-1500} / 1000.0 ))"
        exec {_shai_ac_debounce_fd}< <(sleep "$delay_s" 2>/dev/null; print -r -- "$snapshot")
        zle -F $_shai_ac_debounce_fd _shai_ac_debounce_done
      fi
    fi
  }

  # ── debounce callback ────────────────────────────────────────────────────────
  _shai_ac_debounce_done() {
    local fd=$1 saved_query
    IFS= read -r -u $fd saved_query 2>/dev/null
    zle -F $fd 2>/dev/null
    exec {fd}<&-
    _shai_ac_debounce_fd=-1

    # Only trigger if buffer hasn't changed since debounce started
    if [[ -n "$BUFFER" && "$BUFFER" == "$saved_query" ]] \
        && ! (( _shai_ac_active )) && (( _shai_ac_fd < 0 )); then
      _shai_ac_widget
    fi
  }

  # ── register widgets ─────────────────────────────────────────────────────────
  zle -N _shai_ac_widget
  zle -N _shai_ac_handle_response
  zle -N _shai_ac_fzf
  zle -N _shai_ac_forward_char
  zle -N _shai_ac_end_of_line
  zle -N _shai_ac_debounce_done

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
