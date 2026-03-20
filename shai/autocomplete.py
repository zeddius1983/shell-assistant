"""Smart autocomplete: LLM-backed shell command suggestions.

Architecture notes
──────────────────
Context is built from discrete sources collected in _build_context().
Each source is a separate helper so new sources can be added later without
touching the orchestration logic.  For example, to add man-page context:

    context["man_page"] = _get_man_page(first_word(partial))

then reference it in _build_prompt().  The provider is resolved separately
from the main shai provider so autocomplete can use a faster/cheaper model.
"""

import dataclasses
import json
import os
import re
from pathlib import Path

from .config import Config, ProviderConfig
from .providers import get_provider
from .system_info import get_system_info


AUTOCOMPLETE_SYSTEM_PROMPT = (
    "You are a shell command completion engine. "
    "Given a partial shell command and context, suggest complete shell commands. "
    "Return ONLY a valid JSON array of strings — no explanation, no markdown, no code fences. "
    "Each command must fit on a single line (use ; or && to chain, never literal newlines). "
    "Each command must naturally and logically extend the partial input exactly as typed."
)


# ── Public API ───────────────────────────────────────────────────────────────

def get_suggestions(partial: str, config: Config, count: int) -> list[str]:
    """Return up to `count` complete command suggestions for `partial`."""
    provider_cfg = _resolve_provider(config)
    provider = get_provider(provider_cfg)
    context = _build_context(config)
    prompt = _build_prompt(partial, context, count)
    raw = "".join(provider.stream(AUTOCOMPLETE_SYSTEM_PROMPT, prompt))
    return _parse_suggestions(raw, count)


# ── Context building ─────────────────────────────────────────────────────────
# Add new context sources here as separate functions; reference them in
# _build_context() and _build_prompt().

def _build_context(config: Config) -> dict:
    return {
        "cwd": os.getcwd(),
        "history": _get_history(config.autocomplete.history_lines),
        "system": get_system_info(),
        # Future: "man_page": _get_man_page(first_word)
    }


def _get_history(n: int) -> list[str]:
    """Return the last `n` unique commands from shell history."""
    candidates = [
        Path.home() / ".zsh_history",
        Path.home() / ".bash_history",
    ]
    for path in candidates:
        if not path.exists():
            continue
        try:
            text = path.read_text(errors="ignore")
            seen: set[str] = set()
            lines: list[str] = []
            for line in reversed(text.splitlines()):
                line = line.strip()
                # zsh extended history format: ": timestamp:duration;cmd"
                if line.startswith(": ") and ";" in line:
                    line = line.split(";", 1)[1]
                if line and not line.startswith("#") and line not in seen:
                    seen.add(line)
                    lines.append(line)
                if len(lines) >= n:
                    break
            return list(reversed(lines))
        except OSError:
            pass
    return []


# ── Prompt building ──────────────────────────────────────────────────────────

def _build_prompt(partial: str, context: dict, count: int) -> str:
    sys_info = context["system"]
    lines = [
        f"Partial command: {partial}",
        f"OS: {sys_info.get('os', 'unknown')}",
        f"Current directory: {context['cwd']}",
    ]
    history = context.get("history", [])
    if history:
        lines.append("Recent commands (for personalisation):")
        for cmd in history:
            lines.append(f"  {cmd}")
    lines.append(f"\nReturn exactly {count} complete command suggestions as a JSON array of strings.")
    return "\n".join(lines)


# ── Response parsing ─────────────────────────────────────────────────────────

def _parse_suggestions(raw: str, count: int) -> list[str]:
    text = raw.strip()
    # Strip markdown fences if the model wraps output despite instructions
    text = re.sub(r'^```(?:json)?\s*', '', text)
    text = re.sub(r'\s*```$', '', text.strip())
    try:
        data = json.loads(text)
        if isinstance(data, list):
            return [str(c).strip() for c in data if c][:count]
    except (json.JSONDecodeError, ValueError):
        pass
    # Fallback: extract quoted strings
    matches = re.findall(r'"([^"]+)"', text)
    return matches[:count]


# ── Provider resolution ──────────────────────────────────────────────────────

def _resolve_provider(config: Config) -> ProviderConfig:
    """Return ProviderConfig for autocomplete, honouring per-feature overrides."""
    ac = config.autocomplete
    provider_name = ac.provider or config.provider
    if provider_name not in config.providers:
        raise ValueError(
            f"Autocomplete provider '{provider_name}' not found in config. "
            f"Available: {list(config.providers.keys())}"
        )
    raw = config.providers[provider_name]
    base_url = raw.get("base_url")
    if base_url and os.path.exists("/.dockerenv"):
        base_url = base_url.replace("://localhost:", "://host.docker.internal:")
    pcfg = ProviderConfig(
        type=raw.get("type", "openai"),
        model=raw["model"],
        api_key=raw.get("api_key"),
        base_url=base_url,
    )
    if ac.model:
        pcfg = dataclasses.replace(pcfg, model=ac.model)
    return pcfg
