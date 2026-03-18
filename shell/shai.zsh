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
