#!/usr/bin/env python3
"""
Validate every skill in skills/ against the Agent Skills specification
(agentskills.io) plus a few house rules.

Usage:
    python3 scripts/validate.py [skills_dir]

Exit code is 1 if any error was found. Warnings do not fail the run.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
NAME_MAX = 64
DESC_MAX = 1024
COMPAT_MAX = 500
BODY_SOFT_LINES = 500
SUMMARY_MAX = 160
RESERVED_NAMES = {"claude", "skill", "skills", "agent", "agents"}
KNOWN_KEYS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}

errors: list[str] = []
warnings: list[str] = []


def err(skill: str, msg: str) -> None:
    errors.append(f"{skill}: {msg}")


def warn(skill: str, msg: str) -> None:
    warnings.append(f"{skill}: {msg}")


def split_frontmatter(text: str) -> tuple[str | None, list[str]]:
    """Return (frontmatter_text, body_lines). frontmatter is None if absent."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, lines
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[1:i]), lines[i + 1:]
    return None, lines


def parse_scalars(fm: str) -> dict[str, str]:
    """
    Minimal top-level YAML scalar reader. Enough for the spec's flat schema and
    avoids a PyYAML dependency in CI. Nested keys (metadata:) are recorded as
    present with an empty value.
    """
    out: dict[str, str] = {}
    key = None
    for raw in fm.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw[0] in " \t":  # continuation or nested block
            if key and out.get(key) is not None:
                out[key] = (out[key] + " " + raw.strip()).strip()
            continue
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", raw)
        if not m:
            continue
        key, value = m.group(1), m.group(2).strip()
        if value in (">", "|", ">-", "|-", ">+", "|+"):
            value = ""
        out[key] = value.strip("'\"")
    return out


def check_skill(d: Path) -> None:
    name = d.name
    md = d / "SKILL.md"

    if not md.is_file():
        candidates = [p.name for p in d.iterdir() if p.name.lower() == "skill.md"]
        if candidates:
            err(name, f"file must be named exactly SKILL.md, found {candidates[0]}")
        else:
            err(name, "missing SKILL.md")
        return

    text = md.read_text(encoding="utf-8")
    fm, body = split_frontmatter(text)
    if fm is None:
        err(name, "missing YAML frontmatter delimited by --- on the first line")
        return

    fields = parse_scalars(fm)

    if "<" in fm or ">" in fm:
        err(name, "frontmatter contains angle brackets, which can inject instructions")

    for unknown in set(fields) - KNOWN_KEYS:
        warn(name, f"non-standard frontmatter key '{unknown}'; put extras under metadata:")

    # --- name ---
    n = fields.get("name")
    if not n:
        err(name, "frontmatter is missing 'name'")
    else:
        if n != name:
            err(name, f"frontmatter name '{n}' must match the directory name")
        if len(n) > NAME_MAX:
            err(name, f"name is {len(n)} chars, max is {NAME_MAX}")
        if not NAME_RE.match(n):
            err(name, "name must be lowercase alphanumeric with single internal hyphens")
        if n in RESERVED_NAMES:
            err(name, f"'{n}' is a reserved name")

    # --- description ---
    desc = fields.get("description")
    if not desc:
        err(name, "frontmatter is missing 'description'")
    else:
        if len(desc) > DESC_MAX:
            err(name, f"description is {len(desc)} chars, max is {DESC_MAX}")
        if len(desc) < 40:
            warn(name, "description is very short; it is the only thing that decides activation")
        if not re.search(r"\buse (this|it|when)\b|\bwhen\b|\btrigger", desc, re.I):
            warn(name, "description does not say WHEN to use the skill, only what it does")

    # --- optional fields ---
    compat = fields.get("compatibility")
    if compat and len(compat) > COMPAT_MAX:
        err(name, f"compatibility is {len(compat)} chars, max is {COMPAT_MAX}")

    # --- house metadata read by install.sh ---
    summary = re.search(r"^metadata:\s*\n(?:[ \t]+.*\n)*?[ \t]+summary:[ \t]*(.*)$", fm + "\n", re.M)
    if not summary:
        warn(name, "no metadata.summary; the installer will fall back to a truncated description")
    else:
        s = summary.group(1).strip().strip("'\"")
        if not s:
            err(name, "metadata.summary must be a single non-empty line")
        elif len(s) > SUMMARY_MAX:
            warn(name, f"metadata.summary is {len(s)} chars; keep it under {SUMMARY_MAX}")

    # --- body ---
    if not [ln for ln in body if ln.strip()]:
        err(name, "SKILL.md has no body; frontmatter alone teaches the agent nothing")
    elif len(body) > BODY_SOFT_LINES:
        warn(name, f"body is {len(body)} lines; consider moving detail into references/")

    for sub in d.iterdir():
        if sub.is_dir() and sub.name not in {"scripts", "references", "assets"}:
            warn(name, f"unconventional subdirectory '{sub.name}/'")

    for script in (d / "scripts").glob("*") if (d / "scripts").is_dir() else []:
        if script.is_file() and not script.stat().st_mode & 0o111:
            warn(name, f"scripts/{script.name} is not executable")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "skills")
    if not root.is_dir():
        print(f"error: no such directory: {root}", file=sys.stderr)
        return 1

    dirs = sorted(p for p in root.iterdir() if p.is_dir() and not p.name.startswith("."))
    if not dirs:
        print(f"error: no skills found in {root}", file=sys.stderr)
        return 1

    for d in dirs:
        check_skill(d)

    for w in warnings:
        print(f"warn  {w}")
    for e in errors:
        print(f"ERROR {e}")

    print(f"\n{len(dirs)} skill(s) checked, {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
