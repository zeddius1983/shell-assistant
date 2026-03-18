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

from .config import load_config, save_default_config, CONFIG_PATH, DO_SYSTEM_PROMPT
from .context import get_context
from .providers import get_provider

console = Console()
err_console = Console(stderr=True)


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
      shai config                  # show/init config file
    """
    # --shell-path: print path to the integration script
    if shell_path:
        script = Path(__file__).parent / "shell" / f"shai.{shell_path}"
        click.echo(str(script.resolve()))
        return

    args = list(query)

    # Special sub-command: config
    if args and args[0] == "config":
        _cmd_config()
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
            stream_response(DO_SYSTEM_PROMPT, task, cfg, raw=True)
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
        stream_response(cfg.system_prompt, prompt, cfg, raw=raw)
    except Exception as e:
        err_console.print(f"[red]Error:[/red] {e}")
        sys.exit(1)


def _cmd_config():
    if CONFIG_PATH.exists():
        console.print(f"[bold]Config file:[/bold] {CONFIG_PATH}\n")
        console.print(CONFIG_PATH.read_text())
    else:
        path = save_default_config()
        console.print(f"[green]Created default config:[/green] {path}")
        console.print("\nEdit it to add your API keys and preferred provider.")
