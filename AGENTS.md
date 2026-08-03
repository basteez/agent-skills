# AGENTS.md

This repository is a library of Agent Skills. It contains no application code.

## Layout

- `skills/<name>/SKILL.md` — one directory per skill, directory name matching the frontmatter `name`
- `install.sh` — interactive installer that places skills into a target project or the user profile
- `scripts/validate.py` — spec validator, no dependencies, run from the repo root

## Working here

- Read `CONTRIBUTING.md` before writing or editing a skill. The format rules are strict in places
  where a violation makes the skill silently fail to load rather than error.
- Run `python3 scripts/validate.py` after any change under `skills/`. CI runs the same check.
- When adding a skill, also add a row to the skills table in `README.md`.
- Agent skill directory paths change as tools ship releases. If you touch the agent catalogue in
  `install.sh`, verify each path against that tool's current documentation and update the table in
  `README.md` to match. Do not add a path you have not verified.
- Test `install.sh` against a scratch directory, never against a real project:
  `mkdir /tmp/t && cd /tmp/t && /path/to/install.sh --dry-run --agents all --skills all`

## Style

Skills are written as instructions to a capable colleague: imperative, specific, explaining why a
step matters rather than only that it must happen. No emoji. Prose over bullet fragments where the
reasoning matters.
