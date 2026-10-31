# Authoring skills

## Layout

One directory per skill under `skills/`, named exactly as the `name` in the frontmatter:

```
skills/my-skill/
├── SKILL.md        required
├── scripts/        optional, executable code the agent can run
├── references/     optional, docs the agent loads only when it needs them
└── assets/         optional, templates and other files used in output
```

## Frontmatter

Only `name` and `description` are required. Spec-compliant agents ignore keys they don't know,
so extra metadata belongs under `metadata:` rather than at the top level.

```yaml
---
name: my-skill
description: What it does, and when to use it.
license: MIT
metadata:
  version: "1.0"
---
```

Constraints from the specification:

- **name** — 1-64 characters, lowercase letters, digits and single internal hyphens. No leading,
  trailing or doubled hyphens. Must match the directory name or the skill silently fails to load.
- **description** — 1-1024 characters.
- **compatibility** — optional, max 500 characters, for environment requirements.
- No `<` or `>` anywhere in the frontmatter. Angle brackets can inject unintended instructions
  into the system prompt.

House convention: a skill that is personal rather than tied to a project (a thinking tool, a
working-style habit) sets `scope: user` under `metadata:`. `install.sh` then refuses to place it
in a project tree and points the user at `--scope user`.

## The description is the whole ballgame

At startup an agent loads only the name and description of every installed skill. The body is
read later, and only if the description convinced the agent this skill is relevant. A brilliant
2000-word body behind a lazy one-line description never gets loaded.

So write the description as if it were a search query built from the phrases you actually use.
State both halves: what the skill does, and when to reach for it.

Weak:

```yaml
description: Helps with upstream issues.
```

Strong:

```yaml
description: Scout the upstream repository of a fork for open issues that are genuinely
  available to pick up, and rank them by value to maintainers times tractability. Use this
  whenever the user is inside a fork and asks what they could contribute upstream, wants to
  find an issue worth working on, or mentions opening a PR to the project they forked.
```

Agents under-trigger far more often than they over-trigger, so err toward listing more trigger
phrasings rather than fewer.

## Body

No format is imposed. What tends to work:

- Imperative instructions. "Resolve the upstream repository", not "the skill will resolve…".
- Explain *why* a step matters. A model that understands the reason handles the cases you didn't
  anticipate; a model following a rule it doesn't understand fails silently at the edges.
- Concrete commands with real flags beat prose descriptions of what to run.
- State what the skill must **not** do. Side effects the user didn't ask for are the main way an
  agentic skill causes damage.
- Keep it under roughly 500 lines. Past that, move detail into `references/` and point at it from
  the body so it loads only when needed.
- Don't explain what the tool is. The agent knows what git is.

## Before committing

```bash
python3 scripts/validate.py
```

Then use it for real, on a real task, before deciding it's finished. The gap between a skill that
reads well and a skill that works only shows up in use.
