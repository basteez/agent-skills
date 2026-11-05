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
| [`pr-review-watch`](skills/pr-review-watch/) | Polls GitHub for PRs that request your review (named repos, or the current project's) and reviews each in a throwaway worktree via a subagent, using BMAD's code review, another installed review skill, or a plain review, then approves or requests changes. |
| [`10-10-10`](skills/10-10-10/) | Facilitates Suzy Welch's 10-10-10 technique for personal decisions: each option weighed at 10 minutes, 10 months and 10 years against your own values. User scope only. |

## Install

Clone this repo once. Every install goes through `install.sh`, either into a project or into your
home directory.

```bash
git clone git@github.com:basteez/agent-skills.git ~/src/agent-skills
```

### Into a project

Run the installer from anywhere inside the project you want to equip. It installs at the git
root, or in the current directory outside a repository:

```bash
cd ~/work/some-project
~/src/agent-skills/install.sh
```

It asks which agents you use and which skills you want, shows the plan, and asks for confirmation
before writing anything:

```
Which agents do you use here?
  1) Shared (.agents/skills)        .agents/skills
  2) Claude Code                    .claude/skills
  3) GitHub Copilot / VS Code       .github/skills
  4) Cursor                         .cursor/skills

Select one or more [1 2 ...], 'a' for all, Enter for 1:
```

Both menus take numbers separated by spaces or commas (`1 2 4`, `1,3`), or `a` for everything.
Enter alone picks the shared layout for agents and every skill for skills.

### For your user, in every project

`--scope user` installs into your home directory instead, so the skills are available in every
project without touching any repo. It can run from any directory:

```bash
~/src/agent-skills/install.sh --scope user
```

Skills meant only for personal use, such as `10-10-10`, can only be installed this way (see
[How placement works](#how-placement-works)).

### Options

| Option | Effect |
|---|---|
| `--agents a,b,c` | Install for these agents and skip the menu. Ids: `agents` (shared layout), `claude-code`, `copilot`, `cursor`, or `all`. |
| `--skills a,b,c` | Install these skills by directory name and skip the menu, or `all`. In project scope, user-only skills are skipped with a warning. |
| `--scope project\|user` | `project` (default) writes into the target project; `user` writes into `$HOME`. |
| `--dest PATH` | Target project root, instead of the git root or current directory. Ignored with `--scope user`. |
| `--copy` | Write real files into every agent directory instead of symlinking to the shared one. |
| `--list` | Print the available skills, with summaries and scope, and the agents, then exit. |
| `-y`, `--yes` | Skip the confirmation prompt. |
| `--dry-run` | Print the plan and every action it would take, write nothing. |
| `-h`, `--help` | Show usage. |

Without a terminal (piped, in CI), the installer can't ask, so it falls back to the shared layout
and every skill unless `--agents` and `--skills` say otherwise.

Running it again over an existing install replaces each selected skill with the current version
from this repo, which is how you update after a `git pull`. Skills you didn't select are left
alone.

### Examples

```bash
# One skill for several agents in this project
~/src/agent-skills/install.sh --agents claude-code,copilot,cursor --skills pr-review-watch

# Everything, for every agent, in another project, no questions
~/src/agent-skills/install.sh --dest ~/work/other-project --agents all --skills all --yes

# Committed skills that must work on Windows checkouts too
~/src/agent-skills/install.sh --agents agents,claude-code --skills all --copy

# Personal install for every project, from a dotfiles script
~/src/agent-skills/install.sh --scope user --agents all --skills all --yes

# Only agents that read the shared layout (Codex, Gemini CLI, Goose, ...)
~/src/agent-skills/install.sh --scope user --agents agents --skills pr-review-watch,10-10-10

# Look before you write
~/src/agent-skills/install.sh --list
~/src/agent-skills/install.sh --dry-run --scope user --agents all --skills all
```

### How placement works

Real files go into `.agents/skills/` (`~/.agents/skills/` in user scope), the layout several
agents read directly. It is always written in link mode, even if you didn't select the shared
layout, because the other directories point at it. Every other selected agent gets a relative
symlink pointing back at it, so all agents see one copy and there is nothing to keep in sync. If
the filesystem refuses symlinks, the installer copies instead and says so. Pass `--copy` for real
files everywhere — worth doing if you commit the skills and anyone on the project is on Windows.

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
