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

# Build the base docker run command into an array
_shai_docker_cmd() {
    local _stdin_flag=()
    [ -t 0 ] || _stdin_flag=(-i)
    echo_cmd=(docker run --rm "${_stdin_flag[@]}"
        -e OPENAI_API_KEY
        -e ANTHROPIC_API_KEY
        -v "${_shai_config_dir}:/root/.config/shai:ro"
        -v "${_shai_cache_dir}:/root/.cache/shai:ro"
        "$SHAI_IMAGE"
    )
}

# 'shai do <task>' — ask LLM for a command, confirm, execute on host
_shai_do() {
    mkdir -p "$_shai_config_dir" "$_shai_cache_dir"

    local _cmd=(docker run --rm
        -e OPENAI_API_KEY
        -e ANTHROPIC_API_KEY
        -v "${_shai_config_dir}:/root/.config/shai:ro"
        -v "${_shai_cache_dir}:/root/.cache/shai:ro"
        "$SHAI_IMAGE"
        do
    )

    # Capture full LLM response
    local response
    response=$("${_cmd[@]}" "$@" 2>&1)

    # Display with glow if available, otherwise plain
    if command -v glow > /dev/null 2>&1; then
        printf '%s\n' "$response" | glow -
    else
        printf '%s\n' "$response"
    fi

    # Extract first ```bash ... ``` block
    local extracted_cmd
    extracted_cmd=$(printf '%s\n' "$response" | awk '/^```bash$/{found=1;next} found && /^```/{exit} found{print}')

    if [ -z "$extracted_cmd" ]; then
        printf '\n\033[33mNo executable command found in response.\033[0m\n'
        return 1
    fi

    # Warn on destructive patterns
    local dangerous=0
    case "$extracted_cmd" in
        *"rm "*|*"rm -"*|"rm "*) dangerous=1 ;;
    esac
    case "$extracted_cmd" in
        *"sudo "*|*" dd "*|*"dd if"*|*"mkfs"*|*"| sh"*|*"| bash"*|*"chmod -R"*|*"chown -R"*) dangerous=1 ;;
    esac

    printf '\n'
    [ "$dangerous" -eq 1 ] && printf '\033[33m⚠  Warning: command may be destructive\033[0m\n'
    printf '\033[1mRun? [Y/e/n]\033[0m  '

    local answer
    read -r answer
    case "$answer" in
        y|Y|"")
            printf '\n'
            eval "$extracted_cmd"
            ;;
        e|E)
            printf 'Edit: '
            if [ -n "$ZSH_VERSION" ]; then
                local edited="$extracted_cmd"
                vared edited
                printf '\n'
                eval "$edited"
            else
                local edited
                read -e -i "$extracted_cmd" -r edited
                eval "$edited"
            fi
            ;;
        *)
            printf 'Cancelled.\n'
            ;;
    esac
}

# Internal function — called via the noglob alias below
_shai() {
    mkdir -p "$_shai_config_dir" "$_shai_cache_dir"

    # Dispatch 'do' subcommand to host-side executor
    if [ "$1" = "do" ]; then
        shift
        _shai_do "$@"
        return
    fi

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

    # Check if --raw or -r was passed — only scan leading flags, stop at first non-flag word
    local _raw=0
    for _arg in "$@"; do
        case "$_arg" in
            --raw|-r) _raw=1 ;;
            -*) ;;          # other flag, keep scanning
            *) break ;;     # first non-flag word: stop
        esac
    done

    if [ "$_raw" -eq 0 ] && command -v glow > /dev/null 2>&1; then
        "${_cmd[@]}" "$@" | glow -
    else
        "${_cmd[@]}" "$@"
    fi
}

# noglob prevents zsh from expanding ?, *, ! etc. before passing args to shai
alias shai='noglob _shai'
