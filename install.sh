#!/usr/bin/env bash
#
# Install Agent Skills into a project (or into your user profile).
#
# Run it from the root of the project you want to equip:
#   /path/to/agent-skills/install.sh
#
# Skills are written once to the shared .agents/skills directory and linked
# into each agent's own location, so every agent sees the same copy.
#
set -euo pipefail

VERSION="0.1.0"

# ---------------------------------------------------------------------------
# Agent catalogue
#
# id | label | project dir | user dir (relative to $HOME) | note
#
# Paths are the documented skill locations for each agent. Several agents read
# the shared .agents/skills layout, which is why that entry is the default.
# ---------------------------------------------------------------------------
AGENT_TABLE="
agents|Shared (.agents/skills)|.agents/skills|.agents/skills|Codex, Gemini CLI, Cursor, Copilot, Goose, OpenCode, Amp and others read this
claude-code|Claude Code|.claude/skills|.claude/skills|Also read by VS Code and Copilot
copilot|GitHub Copilot / VS Code|.github/skills|.copilot/skills|Copilot's primary path; travels with the repo
cursor|Cursor|.cursor/skills|.cursor/skills|Cursor also reads .agents/skills
"

# ---------------------------------------------------------------------------
# Defaults, overridable by flags
# ---------------------------------------------------------------------------
SCOPE="project"
MODE="link"          # link | copy
DEST_ROOT=""
SEL_AGENTS=""
SEL_SKILLS=""
ASSUME_YES=0
DRY_RUN=0

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SRC_DIR/skills"

c_bold=$'\033[1m'; c_dim=$'\033[2m'; c_grn=$'\033[32m'; c_ylw=$'\033[33m'; c_off=$'\033[0m'
if [ ! -t 1 ]; then c_bold=""; c_dim=""; c_grn=""; c_ylw=""; c_off=""; fi

say()  { printf '%s\n' "$*"; }
warn() { printf '%s%s%s\n' "$c_ylw" "$*" "$c_off" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
${c_bold}agent-skills installer v$VERSION${c_off}

Usage: install.sh [options]

  --agents a,b,c   Install for these agents (skip the prompt).
                   Available: $(list_agent_ids | tr '\n' ' ')
  --skills a,b,c   Install these skills (skip the prompt). Use 'all' for every skill.
  --scope SCOPE    'project' (default) writes into the current repo.
                   'user' writes into your home directory for every project.
  --copy           Copy skill files instead of symlinking them to .agents/skills.
                   Use this if you commit skills and need Windows checkouts to work.
  --dest PATH      Target project root. Defaults to the git root, else \$PWD.
  --list           Show available skills and agents, then exit.
  -y, --yes        Don't ask for confirmation.
  --dry-run        Print what would happen, change nothing.
  -h, --help       This message.

Examples:
  ./install.sh
  ./install.sh --agents claude-code,copilot --skills all -y
  ./install.sh --scope user --agents agents --skills upstream-issue-scout
EOF
}

# ---------------------------------------------------------------------------
# Catalogue helpers
# ---------------------------------------------------------------------------
agent_rows() { printf '%s\n' "$AGENT_TABLE" | sed '/^[[:space:]]*$/d'; }
list_agent_ids() { agent_rows | cut -d'|' -f1; }

agent_field() { # $1 = id, $2 = field number
  agent_rows | awk -F'|' -v id="$1" -v f="$2" '$1==id {print $f}'
}

list_skills() {
  [ -d "$SKILLS_DIR" ] || die "no skills/ directory next to install.sh (looked in $SRC_DIR)"
  find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md -print0 \
    | xargs -0 -n1 dirname 2>/dev/null \
    | xargs -n1 basename 2>/dev/null \
    | sort
}

# A single-line key under metadata: in the frontmatter, quotes stripped.
skill_meta() { # $1 = skill, $2 = key
  local f="$SKILLS_DIR/$1/SKILL.md"
  [ -f "$f" ] || return 0
  awk -v key="$2" '
    NR==1 && $0 ~ /^---[[:space:]]*$/ { infm=1; next }
    infm && $0 ~ /^---[[:space:]]*$/  { exit }
    infm && $0 ~ /^[^[:space:]]/      { inmeta = ($0 ~ /^metadata:/); next }
    infm && inmeta && $0 ~ "^[[:space:]]+" key ":" {
      sub("^[[:space:]]+" key ":[[:space:]]*", "")
      if ($0 ~ /^".*"$/ || $0 ~ /^\047.*\047$/) $0 = substr($0, 2, length($0) - 2)
      print; exit
    }
  ' "$f"
}

# metadata.summary is a one-line, human-facing description. The spec's
# description field is written to trigger agents, so it is only a fallback.
skill_summary() {
  local s; s="$(skill_meta "$1" summary)"
  if [ -z "$s" ]; then
    s="$(awk '
      NR==1 && $0 ~ /^---[[:space:]]*$/ { infm=1; next }
      infm && $0 ~ /^---[[:space:]]*$/  { exit }
      infm && $0 ~ /^description:/ {
        sub(/^description:[[:space:]]*/, "")
        sub(/^["'"'"'>|-]+[[:space:]]*/, "")
        print; exit
      }
    ' "$SKILLS_DIR/$1/SKILL.md" | awk '{
        if (length($0) > 100) { $0 = substr($0, 1, 100); sub(/[[:space:]]+[^[:space:]]*$/, ""); $0 = $0 "..." }
        print
      }')"
  fi
  printf '%s' "$s"
}

# metadata.scope 'user' marks a skill that only makes sense installed in the
# home directory (personal, not tied to a project).
skill_scope() { skill_meta "$1" scope; }

scope_tag() { [ "$(skill_scope "$1")" = "user" ] && printf ' [user scope]'; return 0; }

# Print text word-wrapped to the terminal, every line prefixed by $1.
wrap() { # $1 = indent, $2 = text
  local width; width="$(tput cols 2>/dev/null || echo 80)"
  [ "$width" -gt 100 ] && width=100
  width=$((width - ${#1}))
  [ "$width" -lt 30 ] && width=30
  printf '%s\n' "$2" | fold -s -w "$width" | sed -e 's/[[:space:]]*$//' -e "s/^/$1/"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --agents) SEL_AGENTS="${2:-}"; shift 2 ;;
    --skills) SEL_SKILLS="${2:-}"; shift 2 ;;
    --scope)  SCOPE="${2:-}"; shift 2 ;;
    --dest)   DEST_ROOT="${2:-}"; shift 2 ;;
    --copy)   MODE="copy"; shift ;;
    --list)   MODE="list"; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

case "$SCOPE" in project|user) ;; *) die "--scope must be 'project' or 'user'" ;; esac

if [ "$MODE" = "list" ]; then
  say "${c_bold}Skills${c_off}"
  while IFS= read -r s; do
    printf '  %s%s%s%s\n' "$c_bold" "$s" "$c_off" "$c_ylw$(scope_tag "$s")$c_off"
    wrap "      " "$(skill_summary "$s")"
  done < <(list_skills)
  say ""
  say "${c_bold}Agents${c_off}"
  agent_rows | while IFS='|' read -r id label pdir udir note; do
    printf '  %-14s %-28s %s\n' "$id" "$label" "$c_dim$note$c_off"
  done
  exit 0
fi

# ---------------------------------------------------------------------------
# Where are we installing?
# ---------------------------------------------------------------------------
if [ "$SCOPE" = "user" ]; then
  DEST_ROOT="$HOME"
elif [ -z "$DEST_ROOT" ]; then
  DEST_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -d "$DEST_ROOT" ] || die "destination does not exist: $DEST_ROOT"

if [ "$SCOPE" = "project" ] && [ "$DEST_ROOT" = "$SRC_DIR" ]; then
  die "refusing to install the skills repo into itself. cd into your project first."
fi

# ---------------------------------------------------------------------------
# Prompting
# ---------------------------------------------------------------------------
TTY="/dev/tty"
have_tty() { [ -r "$TTY" ]; }

ask() { # $1 = prompt, echoes the answer
  local reply=""
  printf '%s' "$1" > "$TTY"
  IFS= read -r reply < "$TTY" || true
  printf '%s' "$reply"
}

# Turn "1 3" / "1,3" / "a" into a newline-separated list of chosen values.
resolve_choice() { # $1 = raw input, $2 = default token, rest = options
  local raw="${1:-}"; local dflt="$2"; shift 2
  local opts=("$@")
  [ -z "$raw" ] && raw="$dflt"
  if [ "$raw" = "a" ] || [ "$raw" = "all" ]; then
    printf '%s\n' "${opts[@]}"
    return
  fi
  local tok
  for tok in $(printf '%s' "$raw" | tr ',' ' '); do
    case "$tok" in
      ''|*[!0-9]*) warn "ignoring '$tok': not a number" ;;
      *)
        if [ "$tok" -ge 1 ] && [ "$tok" -le "${#opts[@]}" ]; then
          printf '%s\n' "${opts[$((tok-1))]}"
        else
          warn "ignoring '$tok': out of range"
        fi
        ;;
    esac
  done
}

AGENT_IDS=()
while IFS= read -r a; do AGENT_IDS+=("$a"); done < <(list_agent_ids)

SKILL_IDS=()
while IFS= read -r s; do SKILL_IDS+=("$s"); done < <(list_skills)
[ "${#SKILL_IDS[@]}" -gt 0 ] || die "no skills found in $SKILLS_DIR"

# --- agents ---
CHOSEN_AGENTS=()
if [ -n "$SEL_AGENTS" ]; then
  for a in $(printf '%s' "$SEL_AGENTS" | tr ',' ' '); do
    if [ "$a" = "all" ]; then CHOSEN_AGENTS=("${AGENT_IDS[@]}"); break; fi
    [ -n "$(agent_field "$a" 1)" ] || die "unknown agent: $a"
    CHOSEN_AGENTS+=("$a")
  done
elif have_tty; then
  say ""
  say "${c_bold}Which agents do you use here?${c_off}"
  i=1
  # Process substitution, not a pipe: a pipe would run this in a subshell and
  # discard every increment of $i, numbering all rows "1".
  while IFS='|' read -r id label pdir udir note; do
    # shellcheck disable=SC2088  # display string only, never used as a path
    if [ "$SCOPE" = "user" ]; then shown="~/$udir"; else shown="$pdir"; fi
    printf '  %d) %-28s %s\n' "$i" "$label" "$c_dim$shown$c_off"
    i=$((i+1))
  done < <(agent_rows)
  say "     ${c_dim}$(agent_field agents 5)${c_off}"
  say ""
  raw="$(ask "Select one or more [1 2 ...], 'a' for all, Enter for 1: ")"
  while IFS= read -r a; do [ -n "$a" ] && CHOSEN_AGENTS+=("$a"); done \
    < <(resolve_choice "$raw" "1" "${AGENT_IDS[@]}")
else
  CHOSEN_AGENTS=("agents")
  warn "no terminal available, defaulting to the shared .agents/skills layout"
fi
[ "${#CHOSEN_AGENTS[@]}" -gt 0 ] || die "no agent selected"

# --- skills ---
CHOSEN_SKILLS=()
if [ -n "$SEL_SKILLS" ]; then
  if [ "$SEL_SKILLS" = "all" ]; then
    CHOSEN_SKILLS=("${SKILL_IDS[@]}")
  else
    for s in $(printf '%s' "$SEL_SKILLS" | tr ',' ' '); do
      [ -d "$SKILLS_DIR/$s" ] || die "unknown skill: $s"
      CHOSEN_SKILLS+=("$s")
    done
  fi
elif have_tty; then
  say ""
  say "${c_bold}Which skills?${c_off}"
  i=1
  for s in "${SKILL_IDS[@]}"; do
    printf '  %d) %s%s\n' "$i" "$s" "$c_ylw$(scope_tag "$s")$c_off"
    printf '%s' "$c_dim"; wrap "     " "$(skill_summary "$s")"; printf '%s' "$c_off"
    i=$((i+1))
  done
  say ""
  raw="$(ask "Select one or more [1 2 ...], Enter for all: ")"
  while IFS= read -r s; do [ -n "$s" ] && CHOSEN_SKILLS+=("$s"); done \
    < <(resolve_choice "$raw" "a" "${SKILL_IDS[@]}")
else
  CHOSEN_SKILLS=("${SKILL_IDS[@]}")
fi
[ "${#CHOSEN_SKILLS[@]}" -gt 0 ] || die "no skill selected"

# Personal skills don't belong in a project tree, where they could be committed.
if [ "$SCOPE" = "project" ]; then
  kept=()
  for s in "${CHOSEN_SKILLS[@]}"; do
    if [ "$(skill_scope "$s")" = "user" ]; then
      warn "skipping $s: user-scope only. Install it with: install.sh --scope user --skills $s"
    else
      kept+=("$s")
    fi
  done
  [ "${#kept[@]}" -gt 0 ] || die "nothing left to install in project scope (try --scope user)"
  CHOSEN_SKILLS=("${kept[@]}")
fi

# ---------------------------------------------------------------------------
# Plan
# ---------------------------------------------------------------------------
dir_for_agent() { # $1 = agent id -> path relative to DEST_ROOT
  if [ "$SCOPE" = "user" ]; then agent_field "$1" 4; else agent_field "$1" 3; fi
}

# The shared directory is where real files land; everything else links to it.
CANON_REL="$(dir_for_agent agents)"

TARGET_DIRS=()
for a in "${CHOSEN_AGENTS[@]}"; do
  d="$(dir_for_agent "$a")"
  dup=0
  for t in "${TARGET_DIRS[@]:-}"; do [ "$t" = "$d" ] && dup=1; done
  [ "$dup" = 0 ] && TARGET_DIRS+=("$d")
done
# The shared dir always gets the real files, even if not explicitly selected.
have_canon=0
for t in "${TARGET_DIRS[@]}"; do [ "$t" = "$CANON_REL" ] && have_canon=1; done
if [ "$have_canon" = 0 ] && [ "$MODE" = "link" ]; then
  TARGET_DIRS=("$CANON_REL" "${TARGET_DIRS[@]}")
fi

say ""
say "${c_bold}Plan${c_off}"
say "  scope   : $SCOPE"
say "  root    : $DEST_ROOT"
say "  method  : $([ "$MODE" = copy ] && echo 'copy files' || echo "real files in $CANON_REL, symlinks elsewhere")"
say "  targets : ${TARGET_DIRS[*]}"
say "  skills  :"
for s in "${CHOSEN_SKILLS[@]}"; do
  say "    $s"
  printf '%s' "$c_dim"; wrap "      " "$(skill_summary "$s")"; printf '%s' "$c_off"
done
say ""

if [ "$ASSUME_YES" = 0 ] && [ "$DRY_RUN" = 0 ] && have_tty; then
  ans="$(ask "Proceed? [Y/n] ")"
  case "$ans" in [nN]*) say "aborted."; exit 0 ;; esac
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
run() { if [ "$DRY_RUN" = 1 ]; then say "  ${c_dim}would: $*${c_off}"; else "$@"; fi; }

# depth of a relative dir, used to build the ../.. prefix for symlinks
up_prefix() {
  local depth; depth="$(printf '%s' "$1" | tr -cd '/' | wc -c | tr -d ' ')"
  local n=$((depth + 1)) out=""
  while [ "$n" -gt 0 ]; do out="../$out"; n=$((n-1)); done
  printf '%s' "$out"
}

installed=0
for target in "${TARGET_DIRS[@]}"; do
  abs="$DEST_ROOT/$target"
  run mkdir -p "$abs"
  for skill in "${CHOSEN_SKILLS[@]}"; do
    src="$SKILLS_DIR/$skill"
    dst="$abs/$skill"

    if [ -e "$dst" ] || [ -L "$dst" ]; then
      run rm -rf "$dst"
    fi

    if [ "$MODE" = "copy" ] || [ "$target" = "$CANON_REL" ]; then
      run cp -R "$src" "$dst"
      printf '  %s%s%s  %s\n' "$c_grn" "+" "$c_off" "$target/$skill"
    else
      link="$(up_prefix "$target")$CANON_REL/$skill"
      if [ "$DRY_RUN" = 1 ]; then
        say "  ${c_dim}would: ln -s $link $dst${c_off}"
      elif ln -s "$link" "$dst" 2>/dev/null; then
        printf '  %s%s%s  %s %s->%s %s\n' "$c_grn" "+" "$c_off" "$target/$skill" "$c_dim" "$c_off" "$CANON_REL/$skill"
      else
        cp -R "$src" "$dst"
        warn "  symlink unsupported here, copied instead: $target/$skill"
      fi
    fi
    installed=$((installed+1))
  done
done

say ""
if [ "$DRY_RUN" = 1 ]; then
  say "Dry run finished. Nothing was written."
  exit 0
fi

say "${c_grn}Installed $installed skill placement(s).${c_off}"
say ""
say "Next:"
say "  - Start your agent and ask \"what skills do you have?\" to confirm discovery."
if [ "$SCOPE" = "project" ]; then
  say "  - Decide whether to commit these directories. Committing shares the skills"
  say "    with everyone on the project; add them to .gitignore to keep them local."
  if [ "$MODE" = "link" ]; then
    say "  - The symlinks are committable, but teammates on Windows may need --copy."
  fi
fi
