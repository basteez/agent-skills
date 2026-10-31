# agent-skills

A personal library of [Agent Skills](https://agentskills.io) — portable folders of instructions
that teach any compatible AI coding agent how to do a specific job well.

The format is an open standard: a directory containing a `SKILL.md` with YAML frontmatter, plus
optional scripts and reference files. The same skill runs unchanged in Claude Code, OpenAI Codex,
GitHub Copilot, VS Code, Cursor, Gemini CLI, Goose, OpenCode and others. Nothing here is tied to
a single vendor.

## Skills

| Skill | What it does |
|---|---|
| [`upstream-issue-scout`](skills/upstream-issue-scout/) | From inside a fork, finds upstream issues that are genuinely free to pick up and ranks them by value to maintainers times tractability for one contributor. |
| [`10-10-10`](skills/10-10-10/) | Facilitates Suzy Welch's 10-10-10 technique for personal decisions: each option weighed at 10 minutes, 10 months and 10 years against your own values. User scope only. |

## Install into a project

Clone this repo once, then run the installer from the root of whatever project you want to equip:

```bash
git clone git@github.com:basteez/agent-skills.git ~/src/agent-skills

cd ~/work/some-project
~/src/agent-skills/install.sh
```

It asks which agents you use and which skills you want, then writes them into the right places:

```
Which agents do you use here?
  1) Shared (.agents/skills)        .agents/skills
  2) Claude Code                    .claude/skills
  3) GitHub Copilot / VS Code       .github/skills
  4) Cursor                         .cursor/skills

Select one or more [1 2 ...], 'a' for all, Enter for 1:
```

Non-interactive, for scripts and dotfiles:

```bash
~/src/agent-skills/install.sh --agents claude-code,copilot --skills all --yes
~/src/agent-skills/install.sh --scope user --agents agents --skills all --yes
~/src/agent-skills/install.sh --list
~/src/agent-skills/install.sh --dry-run --agents all --skills all
```

### How placement works

Real files go into `.agents/skills/`, the layout several agents read directly. Every other
selected agent gets a relative symlink pointing back at it, so all agents see one copy and there
is nothing to keep in sync. Pass `--copy` for real files everywhere — worth doing if you commit
the skills and anyone on the project is on Windows.

`--scope user` installs into your home directory instead, making the skills available in every
project without touching any repo.

Some skills are personal rather than project tooling and declare `scope: user` under
`metadata:` in their frontmatter. The installer skips them with a warning in project scope, so
they can't end up committed to a repo; install them with `--scope user`.

### Where each agent looks

| Agent | Project | Personal |
|---|---|---|
| Shared layout — Codex, Gemini CLI, Goose, OpenCode, Amp, Rovo Dev | `.agents/skills/` | `~/.agents/skills/` |
| Claude Code | `.claude/skills/` | `~/.claude/skills/` |
| GitHub Copilot, VS Code | `.github/skills/` (also reads `.claude/skills`, `.agents/skills`) | `~/.copilot/skills/` |
| Cursor | `.cursor/skills/` (also reads `.agents/skills`) | `~/.cursor/skills/` |

Paths drift as tools ship new versions. If an agent doesn't pick a skill up, check its current
docs and open an issue here so the table and the installer catalogue can be corrected.

### Committing or not

Both are reasonable. Committing `.agents/skills/` shares the skills with everyone on the project
and puts them under review like any other config. Keeping them out of version control via
`.gitignore` suits skills that encode personal working style rather than project rules. The
installer doesn't decide for you.

## Adding a skill

```bash
mkdir -p skills/my-skill
$EDITOR skills/my-skill/SKILL.md
python3 scripts/validate.py
```

`CONTRIBUTING.md` has the format rules and the parts that actually determine whether a skill
gets used. The short version: the description is the only thing an agent reads when deciding
whether to load a skill, so it has to state both what the skill does and when to reach for it.

## Validation

```bash
python3 scripts/validate.py          # checks every skill in skills/
```

Checks the spec constraints — name pattern and length, description length, exact `SKILL.md`
casing, name matching the directory, no angle brackets in frontmatter — plus house rules like
body length and unknown frontmatter keys. CI runs it on every push and pull request.

## A note on trust

Skills are instructions that an agent will follow with your tools and your credentials. Public
skill registries have already shipped malicious ones: a 2026 audit found prompt injection in a
large share of published skills, and over a thousand malicious packages were pulled from one
registry. Read anything you copy in here before installing it, the same way you would with a
dependency. Everything in this repo is written to be read.

## License

MIT. See `LICENSE`.
