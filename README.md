# shai — Shell AI

![Built with AI assistance](https://img.shields.io/badge/Built%20with-AI%20assistance-blueviolet?logo=openai&logoColor=white)

LLM-powered assistant for your terminal. Get contextual help from your local or cloud LLM based on what just happened in your shell — errors, failed commands, unexpected output.

Inspired by [PEEL](https://github.com/lemonade-sdk/peel) for PowerShell.

```
$ git pull-request
git: 'pull-request' is not a git command. See 'git --help'.

$ shai help
The command `git pull-request` is not valid. Use `git pull` to fetch and
merge, or install the `gh` CLI and run `gh pr create` to open a pull request.
```

---

## How it works

Shell hooks (`PROMPT_COMMAND` / `precmd`) save your terminal's scrollback after every command. When you run `shai help`, the saved context is sent to your LLM of choice. No copy-pasting, no switching windows.

With tmux, the full screen output (including stderr) is captured. Without tmux, the last command and exit code are saved as fallback.

---

## Installation

### One-line install (recommended)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/zeddius1983/shell-assistant/main/install.sh)"
```

This will:
1. Install [uv](https://docs.astral.sh/uv/) if it isn't already present
2. Install shai via `uv tool install shai`
3. Add the shell integration line to your `~/.zshrc` or `~/.bashrc`

Then reload your shell and create your config:

```bash
source ~/.zshrc      # or ~/.bashrc
shai /config         # create config and add your API key
```

### Alternative: pipx

```bash
pipx install shai
```

Then add shell integration manually — add one of the following to your shell RC file:

```zsh
# ~/.zshrc
source "$(shai --shell-path zsh)"
```

```bash
# ~/.bashrc
source "$(shai --shell-path bash)"
```

### Alternative: Docker (no Python required)

```bash
docker pull ghcr.io/zeddius1983/shell-assistant:latest

# Or build locally:
git clone https://github.com/zeddius1983/shell-assistant
cd shell-assistant
docker build -t shai:local .
```

Add to `~/.zshrc` or `~/.bashrc`:

```bash
export SHAI_IMAGE="ghcr.io/zeddius1983/shell-assistant:latest"  # or shai:local
source /path/to/shell-assistant/shell/shai-docker.sh
```

### Alternative: build from source

```bash
git clone https://github.com/zeddius1983/shell-assistant
cd shell-assistant
uv tool install .
```

---

## Usage

```bash
# Explain what just went wrong
shai help

# Ask anything shell-related
shai how to list all datasets in a ZFS pool
shai what does SIGKILL mean
shai how do I find which process is using port 8080

# Let shai do it — generates a command, shows it, asks before running
shai do find the largest file in ~/Downloads
shai do show disk usage by folder in /var
shai do list all listening ports

# Tip: quote the task if it contains apostrophes or special characters
shai do "show all files modified in the last week"
shai do "find the largest file and show it's size in MB"

# Pipe output directly (no shell hook needed)
kubectl get pods 2>&1 | shai
journalctl -xe | shai why is nginx failing

# Skip context, ask a clean question
shai --no-context explain the difference between hard and soft links

# Raw output — no glow or rich rendering
shai --raw how do I list open ports
shai -r help

# Use a specific provider or model for one query
shai -p anthropic help
shai -p openai -m gpt-4o how do I list listening ports
```

### Subcommands

| Command | Description |
|---|---|
| `shai help` | Analyse your last terminal output and explain errors |
| `shai do <task>` | Generate a shell command, preview it, confirm before running |
| `shai /config` | Show the active config file, or create a default one |
| `shai /context` | Show the full system prompt and captured terminal context |
| `shai /stats` | Show provider, model, context size, and system info |

### Flags

| Flag | Short | Description |
|---|---|---|
| `--no-context` | | Skip attaching terminal context |
| `--raw` | `-r` | Disable glow and rich rendering, stream plain text |
| `--provider <name>` | `-p` | Override the active provider for this query |
| `--model <name>` | `-m` | Override the model for this query |

---

## Configuration

Generate the default config file:
```bash
shai /config
```

This creates `~/.config/shai/config.yaml`:

```yaml
provider: lmstudio        # active provider

providers:
  lmstudio:               # LM Studio (or any OpenAI-compatible local server)
    type: openai
    base_url: http://localhost:1234/v1
    api_key: lmstudio
    model: google/gemma-3-4b

  ollama:
    type: openai
    base_url: http://localhost:11434/v1
    api_key: ollama
    model: llama3.2

  openai:
    type: openai
    model: gpt-4o
    api_key: sk-...       # or set OPENAI_API_KEY env var

  anthropic:
    type: anthropic
    model: claude-sonnet-4-6
    api_key: sk-ant-...   # or set ANTHROPIC_API_KEY env var

  # Any OpenAI-compatible endpoint (vLLM, llama.cpp, etc.)
  custom:
    type: openai
    base_url: http://myserver:8080/v1
    api_key: none
    model: my-model
```

---

## Supported providers

| Provider | `type` | Notes |
|---|---|---|
| [LM Studio](https://lmstudio.ai) | `openai` | Default. Set `base_url: http://localhost:1234/v1` |
| [Ollama](https://ollama.com) | `openai` | Set `base_url: http://localhost:11434/v1` |
| [OpenAI](https://platform.openai.com) | `openai` | Set `OPENAI_API_KEY` |
| [Anthropic](https://anthropic.com) | `anthropic` | Set `ANTHROPIC_API_KEY` |
| llama.cpp / vLLM / any OpenAI-compatible | `openai` | Set `base_url` to your server |

> **Docker note:** `localhost` in your config is automatically rewritten to `host.docker.internal` when shai runs inside a container, so local servers are always reachable.

---

## 🧰 Shai Toolbox & Terminal Setup

Shai works out of the box in any terminal, but we provide a cross-platform, idempotent **interactive installer** to perfectly configure your environment with the best modern Rust-based terminal tools (which Shai can deeply integrate with).

Instead of installing things manually, just run:

```bash
./shell/setup.sh
```

This launches the **Shai Toolbox interactive menu**, allowing you to seamlessly toggle `[x]` install or `[ ]` completely uninstall the following recommended integrations natively via `brew` or `apt`:

### git-delta — drastically better git diffs

[git-delta](https://github.com/dandavison/delta) acts as a syntax-highlighting pager for git. The toolbox automatically sets it as your global `core.pager` and configures it for modern diff layouts.

**Usage Examples:**
```bash
# Every standard git command is now beautifully syntax-highlighted and side-by-side
git diff
git show
git log -p

# Shai can also use delta to highlight the diff patches it generates
git diff | shai "why is this failing?"
```

### glow — markdown rendering

shai pipes its responses through [glow](https://github.com/charmbracelet/glow) when available, giving you properly rendered markdown with syntax-highlighted code blocks.

```bash
brew install glow
```

Without glow, shai falls back to rich's live markdown renderer inside the container.

### Starship — prompt

[Starship](https://starship.rs) is a fast, cross-shell prompt. It shows git branch, Python version, Docker context, and more — useful context when working alongside shai.

```bash
brew install starship
```

Add to `~/.zshrc` (must be the last line):
```zsh
eval "$(starship init zsh)"
```

**Recommended `~/.config/starship.toml`** for use with shai:

```toml
format = """
$directory$git_branch$git_status$python$docker_context
$character"""

[directory]
truncation_length = 3
truncate_to_repo = true

[git_branch]
symbol = " "
style = "bold purple"

[git_status]
ahead = "⇡${count}"
behind = "⇣${count}"
diverged = "⇕⇡${ahead_count}⇣${behind_count}"
modified = "!${count}"
untracked = "?${count}"
staged = "+${count}"

[python]
symbol = "🐍 "
format = "via [${symbol}v${version}](yellow) "

[docker_context]
symbol = "🐳 "
format = "via [${symbol}${context}](blue bold) "
only_with_files = false

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
```

This prompt clearly shows your active directory, git state, Python environment, and Docker context at a glance — so shai always has relevant visual context alongside the captured terminal scrollback.

### eza — better `ls`

[eza](https://eza.rocks) is a modern `ls` replacement with colour coding, icons, and git status. When you ask `shai do list files`, the output it works from is much richer.

```bash
brew install eza
```

**Recommended aliases** — add to `~/.zshrc`:

```zsh
alias ls='eza --icons --group-directories-first'
alias ll='eza --icons --group-directories-first -l --git'
alias la='eza --icons --group-directories-first -la --git'
alias lt='eza --icons --tree --level=2'
alias lta='eza --icons --tree --level=2 -a'
```

### zsh-syntax-highlighting

Highlights valid commands green and unknown commands red as you type.

```bash
brew install zsh-syntax-highlighting
```

Add to `~/.zshrc` (after all other sourcing):
```zsh
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
```

### zsh-autosuggestions

Shows grey completions from your history as you type — press `→` to accept.

```bash
brew install zsh-autosuggestions
```

Add to `~/.zshrc`:
```zsh
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
```

---

## Development

```bash
git clone https://github.com/zeddius1983/shell-assistant
cd shell-assistant

# Install dev environment
uv sync

# Run directly without installing
.venv/bin/shai --help

# Build a wheel
uv build
# → dist/shai-0.1.0-py3-none-any.whl
```

### Publishing to PyPI

```bash
uv build
uv publish
```

### Publishing to GitHub Container Registry

Push to `main` or create a version tag — the included GitHub Actions workflow builds and pushes automatically:

```bash
git tag v0.1.0
git push origin v0.1.0
# → ghcr.io/zeddius1983/shell-assistant:0.1.0 and :latest
```
