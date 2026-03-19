import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

import click
from rich.console import Console
from rich.live import Live
from rich.markdown import Markdown
from rich.text import Text

from rich.panel import Panel
from rich.syntax import Syntax
from rich.table import Table

from .config import load_config, save_default_config, CONFIG_PATH, DO_SYSTEM_PROMPT
from .config import CONTEXT_FILE
from .system_info import format_for_prompt, get_system_info
from .context import get_context
from .providers import get_provider

import os as _os
_term_width = _os.get_terminal_size().columns if _os.isatty(1) else 120
console = Console(width=_term_width)
err_console = Console(stderr=True, width=_term_width)


def build_prompt(question: str, context: Optional[str]) -> str:
    if context:
        return (
            f"Terminal context (recent session output):\n"
            f"```\n{context}\n```\n\n"
            f"{question}"
        )
    return question


def stream_response(system: str, prompt: str, cfg, raw: bool = False) -> None:
    provider = get_provider(cfg.get_active_provider())
    buffer = ""

    if raw:
        try:
            for chunk in provider.stream(system, prompt):
                print(chunk, end="", flush=True)
        except KeyboardInterrupt:
            pass
        print()
    elif shutil.which("glow"):
        # Buffer with a spinner, then render with glow
        try:
            with Live(
                Text("  thinking…", style="dim"),
                console=console,
                refresh_per_second=12,
                transient=True,
            ) as live:
                for chunk in provider.stream(system, prompt):
                    buffer += chunk
                    word_count = len(buffer.split())
                    live.update(Text(f"  thinking… ({word_count} words)", style="dim"))
        except KeyboardInterrupt:
            pass
        if buffer:
            subprocess.run(["glow", "-"], input=buffer.encode(), check=False)
    else:
        # Fallback: live rich markdown rendering
        try:
            with Live(Markdown(""), console=console, refresh_per_second=12, vertical_overflow="visible") as live:
                for chunk in provider.stream(system, prompt):
                    buffer += chunk
                    live.update(Markdown(buffer))
        except KeyboardInterrupt:
            pass


@click.command(
    context_settings={
        "ignore_unknown_options": True,
        "allow_extra_args": True,
        "allow_interspersed_args": False,  # flags must come before the query
    }
)
@click.argument("query", nargs=-1)
@click.option("--no-context", is_flag=True, help="Do not attach terminal context.")
@click.option("--raw", "-r", is_flag=True, help="Stream raw text, disabling glow and rich rendering.")
@click.option("--provider", "-p", default=None, help="Override the active provider.")
@click.option("--model", "-m", default=None, help="Override the model.")
@click.option(
    "--shell-path",
    type=click.Choice(["bash", "zsh"]),
    default=None,
    help="Print path to shell integration script (for sourcing).",
)
@click.pass_context
def main(ctx, query, no_context, raw, provider, model, shell_path):
    """shai — Shell AI assistant.

    \b
    Examples:
      shai help                    # explain the last error in your terminal
      shai how do I list open ports
      git pull-request 2>&1 | shai # pipe any output as context
      shai /config                 # show/init config file
    """
    # --shell-path: print path to the integration script
    if shell_path:
        script = Path(__file__).parent / "shell" / f"shai.{shell_path}"
        click.echo(str(script.resolve()))
        return

    args = list(query)

    # Special sub-commands
    if args and args[0] in ("/config", "config"):
        _cmd_config()
        return
    if args and args[0] == "/context":
        _cmd_context(provider, model)
        return
    if args and args[0] == "/stats":
        _cmd_stats(provider, model)
        return

    try:
        cfg = load_config()
    except Exception as e:
        err_console.print(f"[red]Config error:[/red] {e}")
        err_console.print(f"Run [bold]shai config[/bold] to generate a default config.")
        sys.exit(1)

    # Apply CLI overrides
    if provider:
        cfg.provider = provider
    if model:
        if cfg.provider in cfg.providers:
            cfg.providers[cfg.provider]["model"] = model

    # Special sub-command: do
    if args and args[0] == "do":
        task = " ".join(args[1:])
        if not task:
            err_console.print("[red]Usage:[/red] shai do <task description>")
            sys.exit(1)
        try:
            system = DO_SYSTEM_PROMPT + "\n\n" + format_for_prompt()
            stream_response(system, task, cfg, raw=True)
        except Exception as e:
            err_console.print(f"[red]Error:[/red] {e}")
            sys.exit(1)
        return

    # Determine mode: help (analyse context for errors) vs question (answer directly)
    is_help = args in ([], ["help"])

    if is_help:
        question = "What went wrong in my terminal session above? How do I fix it?"
    else:
        question = " ".join(args)

    # Gather context — always for help mode, skip for plain questions unless piped
    if no_context:
        context = None
    elif is_help:
        context = get_context(cfg.context_lines)
    else:
        # For questions, only use context if explicitly piped (real FIFO/file on stdin)
        from .context import _stdin_has_data
        context = get_context(cfg.context_lines) if _stdin_has_data() else None

    if context is None and not no_context and is_help:
        err_console.print(
            "[yellow]No terminal context found.[/yellow] "
            "Source the shai shell integration or run inside tmux.\n"
            "Tip: pipe output directly with [bold]cmd 2>&1 | shai[/bold]"
        )

    prompt = build_prompt(question, context)

    try:
        system = cfg.system_prompt + "\n\n" + format_for_prompt()
        stream_response(system, prompt, cfg, raw=raw)
    except Exception as e:
        err_console.print(f"[red]Error:[/red] {e}")
        sys.exit(1)


def _cmd_config():
    # When running inside Docker the container path (/root/.config/…) is not useful
    # to the user — show the host path passed via SHAI_HOST_CONFIG_DIR instead.
    import os as _os
    host_config_dir = _os.environ.get("SHAI_HOST_CONFIG_DIR")
    display_path = Path(host_config_dir) / "config.yaml" if host_config_dir else CONFIG_PATH

    if CONFIG_PATH.exists():
        console.print(f"[bold]Config file:[/bold] {display_path}\n")
        console.print(CONFIG_PATH.read_text())
    else:
        save_default_config()
        console.print(f"[green]Created default config:[/green] {display_path}")
        console.print("\nEdit it to add your API keys and preferred provider.")


def _cmd_context(provider_override, model_override):
    """Print the full system prompt + terminal context that would be sent to the LLM."""
    try:
        cfg = load_config()
    except Exception as e:
        err_console.print(f"[red]Config error:[/red] {e}")
        sys.exit(1)
    if provider_override:
        cfg.provider = provider_override
    if model_override and cfg.provider in cfg.providers:
        cfg.providers[cfg.provider]["model"] = model_override

    system = cfg.system_prompt + "\n\n" + format_for_prompt()
    context = get_context(cfg.context_lines)

    console.print(Panel(system, title="[bold cyan]System Prompt[/bold cyan]", border_style="cyan"))
    console.print()
    if context:
        console.print(Panel(
            Syntax(context, "text", theme="ansi_dark", word_wrap=True),
            title="[bold yellow]Terminal Context[/bold yellow]",
            border_style="yellow",
        ))
        est_tokens = len((system + context).split()) * 4 // 3
        console.print(f"\n[dim]~{len(context.splitlines())} lines · ~{est_tokens} tokens estimated[/dim]")
    else:
        console.print(Panel("[dim]No context captured yet.[/dim]",
                            title="[bold yellow]Terminal Context[/bold yellow]",
                            border_style="yellow"))


def _cmd_stats(provider_override, model_override):
    """Print provider, model, context, and system info stats."""
    try:
        cfg = load_config()
    except Exception as e:
        err_console.print(f"[red]Config error:[/red] {e}")
        sys.exit(1)
    if provider_override:
        cfg.provider = provider_override
    if model_override and cfg.provider in cfg.providers:
        cfg.providers[cfg.provider]["model"] = model_override

    pcfg = cfg.get_active_provider()
    sys_info = get_system_info()
    context = get_context(cfg.context_lines)
    context_lines_actual = len(context.splitlines()) if context else 0
    context_chars = len(context) if context else 0
    est_tokens = context_chars * 4 // 15  # rough estimate

    system_prompt = cfg.system_prompt + "\n\n" + format_for_prompt()
    system_tokens = len(system_prompt.split()) * 4 // 3

    import os as _os
    host_config_dir = _os.environ.get("SHAI_HOST_CONFIG_DIR")
    host_cache_dir  = _os.environ.get("SHAI_HOST_CACHE_DIR")
    display_config_path  = str(Path(host_config_dir) / "config.yaml") if host_config_dir else str(CONFIG_PATH)
    display_context_path = str(Path(host_cache_dir) / "context") if host_cache_dir else str(CONTEXT_FILE)

    t = Table(show_header=False, box=None, padding=(0, 2))
    t.add_column(style="bold cyan", no_wrap=True)
    t.add_column()

    t.add_row("Provider", cfg.provider)
    t.add_row("Type", pcfg.type)
    t.add_row("Model", pcfg.model)
    t.add_row("Base URL", pcfg.base_url or "[dim]default[/dim]")
    t.add_row("", "")
    t.add_row("Context limit", f"{cfg.context_lines} lines (max)")
    t.add_row("Context captured", f"{context_lines_actual} lines · {context_chars} chars · ~{est_tokens} tokens")
    t.add_row("System prompt", f"~{system_tokens} tokens")
    t.add_row("Context file", display_context_path)
    t.add_row("Config file", display_config_path)
    t.add_row("", "")
    t.add_row("OS", sys_info["os"])
    t.add_row("Architecture", sys_info["arch"])
    t.add_row("Shell", sys_info["shell"])
    t.add_row("Memory", sys_info["memory"])
    t.add_row("Package manager", sys_info["package_manager"] or "[dim]none detected[/dim]")

    console.print(Panel(t, title="[bold green]shai stats[/bold green]", border_style="green"))
