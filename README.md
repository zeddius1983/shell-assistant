# shai — Shell AI

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

### Option A — Python (uv, recommended)

Requires Python 3.9+ and [uv](https://docs.astral.sh/uv/).

```bash
uv tool install git+https://github.com/youruser/shai

# Or from a cloned repo:
git clone https://github.com/youruser/shai
cd shai
uv tool install .
```

### Option B — pipx

```bash
pipx install git+https://github.com/youruser/shai
```

### Option C — Docker (no Python required)

```bash
docker pull ghcr.io/youruser/shai:latest

# Or build locally:
git clone https://github.com/youruser/shai
cd shai
docker build -t shai:local .
```

---

## Shell integration

Source the integration script in your shell RC file. This installs the context-capture hook and (for Docker) the `shai` wrapper function.

### Native install (Python/uv/pipx)

**zsh** — add to `~/.zshrc`:
```zsh
source "$(shai --shell-path zsh)"
```

**bash** — add to `~/.bashrc`:
```bash
source "$(shai --shell-path bash)"
```

### Docker install

**zsh** — add to `~/.zshrc`:
```zsh
export SHAI_IMAGE="ghcr.io/youruser/shai:latest"  # or shai:local
source /path/to/shai/shell/shai-docker.zsh
```

**bash** — add to `~/.bashrc`:
```bash
export SHAI_IMAGE="ghcr.io/youruser/shai:latest"
source /path/to/shai/shell/shai-docker.bash
```

Then reload your shell:
```bash
source ~/.zshrc   # or ~/.bashrc
```

---

## Configuration

Generate the default config file:
```bash
shai config
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

Switch providers on the fly:
```bash
shai -p anthropic help
shai -p openai -m gpt-4o how do I list listening ports
```

---

## Usage

```bash
# Explain what just went wrong
shai help

# Ask anything shell-related (uses terminal context automatically)
shai how to list all datasets in a ZFS pool
shai what does SIGKILL mean
shai how do I find which process is using port 8080

# Pipe output directly (no shell hook needed)
kubectl get pods 2>&1 | shai
journalctl -xe | shai why is nginx failing

# Skip context, ask a clean question
shai --no-context explain the difference between hard and soft links

# Use a specific provider for one query
shai -p anthropic help
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

## Building from source

```bash
git clone https://github.com/youruser/shai
cd shai

# Install dev environment
uv sync

# Run directly
.venv/bin/shai --help

# Build a wheel
uv build
# → dist/shai-0.1.0-py3-none-any.whl

# Build Docker image
docker build -t shai:local .
```

### Publishing to GitHub Container Registry

Push to `main` or create a version tag — the included GitHub Actions workflow builds and pushes automatically:

```bash
git tag v0.1.0
git push origin v0.1.0
# → ghcr.io/youruser/shai:0.1.0 and :latest
```

Or push manually:
```bash
docker build -t ghcr.io/youruser/shai:latest .
docker push ghcr.io/youruser/shai:latest
```
