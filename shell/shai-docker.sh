# shai Docker integration — works in bash and zsh
#
# Add to ~/.zshrc or ~/.bashrc / ~/.bash_profile:
#   source /path/to/shai/shell/shai-docker.sh
#
# Override the image:
#   export SHAI_IMAGE="ghcr.io/youruser/shai:latest"

if [ "$(uname)" = "Darwin" ]; then
    _shai_cache_dir="$HOME/Library/Caches/shai"
else
    _shai_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/shai"
fi
_shai_context_file="$_shai_cache_dir/context"
_shai_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/shai"
SHAI_IMAGE="${SHAI_IMAGE:-ghcr.io/youruser/shai:latest}"

_shai_save_context() {
    local exit_code=$?
    mkdir -p "$_shai_cache_dir"

    if [ -n "$TMUX" ]; then
        tmux capture-pane -p -S -200 2>/dev/null > "$_shai_context_file"
    else
        local last_cmd
        last_cmd=$(fc -ln -1 2>/dev/null | sed 's/^[[:space:]]*//')
        {
            echo "$ ${last_cmd}"
            [ "$exit_code" -ne 0 ] && echo "[exited with code $exit_code]"
        } > "$_shai_context_file"
    fi
    return $exit_code
}

# Register the precmd/PROMPT_COMMAND hook for the current shell
if [ -n "$ZSH_VERSION" ]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _shai_save_context
elif [ -n "$BASH_VERSION" ]; then
    if [[ "$PROMPT_COMMAND" != *"_shai_save_context"* ]]; then
        PROMPT_COMMAND="_shai_save_context${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
    fi
fi

# Internal function — called via the noglob alias below
_shai() {
    mkdir -p "$_shai_config_dir" "$_shai_cache_dir"

    # Build docker command as an array to avoid any glob re-expansion
    local _cmd=(docker run --rm)
    [ -t 0 ] || _cmd+=(-i)
    _cmd+=(
        -e OPENAI_API_KEY
        -e ANTHROPIC_API_KEY
        -v "${_shai_config_dir}:/root/.config/shai:ro"
        -v "${_shai_cache_dir}:/root/.cache/shai:ro"
        "$SHAI_IMAGE"
    )

    # Check if --raw or -r was passed
    local _raw=0
    for _arg in "$@"; do
        [ "$_arg" = "--raw" ] || [ "$_arg" = "-r" ] && _raw=1 && break
    done

    if [ "$_raw" -eq 0 ] && command -v glow > /dev/null 2>&1; then
        "${_cmd[@]}" "$@" | glow -
    else
        "${_cmd[@]}" "$@"
    fi
}

# noglob prevents zsh from expanding ?, *, ! etc. before passing args to shai
alias shai='noglob _shai'
