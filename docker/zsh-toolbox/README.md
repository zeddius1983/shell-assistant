# Shai Test Environment

This directory contains a pre-configured Ubuntu 24.04 environment built to test [shai](https://github.com/zeddius1983/shell-assistant) locally with all the modern tools and plugins.

## Getting Started

Start the environment using `docker compose`:
```bash
docker-compose up -d
docker-compose exec shai-test zsh
```

## Tools Shipped

This environment is loaded with the following modern command-line tools:

### Base Shell Tools
* **zsh**: The default shell.
* **zsh-syntax-highlighting**: Provides real-time syntax highlighting for commands as you type.
* **zsh-autosuggestions**: Suggests commands based on your history (press `→` to accept).

### Prompt & Navigation
* **Starship** (`starship`): Fast, customizable prompt. Pre-configured here to optimally display git, docker, java, and python contexts.
* **Zoxide** (`zoxide`): A smarter `cd` command. It remembers which directories you use most frequently, so you can jump to them in just a few keystrokes.
  * *Example*: `z shai` (jumps to the shai directory)
* **Atuin** (`atuin`): Replaces your existing shell history with a SQLite database. Press `<Ctrl-R>` to access an interactive search UI for your command history.

### Information & Search
* **eza** (`eza`): A modern replacement for `ls`.
  * *Aliases provided*:
    * `ls`: standard list with icons.
    * `ll`: detailed list with git statuses.
    * `la`: detailed list including hidden files.
    * `lt` / `lta`: tree views.
* **bat** (`bat`): A `cat` clone with advanced syntax highlighting and git integration.
  * *Example*: `bat Dockerfile`
* **ripgrep** (`rg`): An incredibly fast search tool (a modern alternative to `grep`).
  * *Example*: `rg "TODO" .`
* **fd** (`fd`): A modern, fast, and user-friendly alternative to `find`.
  * *Example*: `fd -e md` (finds all Markdown files)
* **fzf** (`fzf`): A general-purpose command-line fuzzy finder. Often used in conjunction with other tools.

### Environment & Rendering
* **direnv** (`direnv`): Unclutters your `.profile` and lets you load/unload environment variables depending on the current directory (`.envrc`).
* **glow** (`glow`): A terminal-based markdown reader used by `shai` to render AI output beautifully.

### Shai
* **shai**: Your Shell AI assistant. It's configured to use your local config mounted from `~/.config/shai`.
  * *Example*: `shai help`
