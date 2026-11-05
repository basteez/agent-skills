#!/usr/bin/env bash
# Create or remove a throwaway worktree holding a pull request's head commit.
#
# Usage:
#   worktree.sh add OWNER/REPO NUMBER [--clone DIR]   prints the worktree path
#   worktree.sh remove PATH
#
# 'add' looks for a local clone of OWNER/REPO in this order: --clone DIR, the
# current directory's repository if one of its remotes points at OWNER/REPO,
# then a blobless cache clone under ${XDG_CACHE_HOME:-~/.cache}/pr-review-watch,
# created on first use. The worktree is detached at the PR head and lives under
# ${TMPDIR:-/tmp}/pr-review-watch, never inside the user's checkout, so the
# user's branch and working tree are untouched.
set -euo pipefail

die() { echo "worktree.sh: $*" >&2; exit 1; }

remote_for() { # $1 = git dir, $2 = owner/repo; prints the matching remote name
  git -C "$1" remote -v 2>/dev/null | awk -v want="$2" '
    $3 == "(fetch)" {
      url = tolower($2); sub(/\.git$/, "", url)
      if (url ~ ("[:/]" tolower(want) "$")) { print $1; exit }
    }'
}

cmd_add() {
  local repo="${1:-}" num="${2:-}" clone=""
  [ -n "$repo" ] && [ -n "$num" ] || die "usage: worktree.sh add OWNER/REPO NUMBER [--clone DIR]"
  shift 2
  [ "${1:-}" = "--clone" ] && clone="${2:-}"

  local remote=""
  if [ -n "$clone" ]; then
    remote="$(remote_for "$clone" "$repo")"
    [ -n "$remote" ] || die "$clone has no remote pointing at $repo"
  elif top="$(git rev-parse --show-toplevel 2>/dev/null)" && remote="$(remote_for "$top" "$repo")" && [ -n "$remote" ]; then
    clone="$top"
  else
    clone="${XDG_CACHE_HOME:-$HOME/.cache}/pr-review-watch/repos/$repo"
    if [ ! -d "$clone/.git" ]; then
      mkdir -p "$(dirname "$clone")"
      gh repo clone "$repo" "$clone" -- --filter=blob:none --no-checkout --quiet >&2
    fi
    remote="origin"
  fi

  local ref="refs/pr-review-watch/pr-$num"
  local path="${TMPDIR:-/tmp}"; path="${path%/}/pr-review-watch/${repo//\//-}-pr-$num"

  if [ -e "$path" ]; then
    git -C "$clone" worktree remove --force "$path" 2>/dev/null || rm -rf "$path"
    git -C "$clone" worktree prune
  fi

  local base
  base="$(gh pr view "$num" -R "$repo" --json baseRefName --jq .baseRefName)"
  git -C "$clone" fetch --quiet "$remote" "+pull/$num/head:$ref" "+refs/heads/$base:refs/remotes/$remote/$base" >&2
  mkdir -p "$(dirname "$path")"
  git -C "$clone" worktree add --quiet --detach "$path" "$ref" >&2
  printf '%s\n' "$path"
}

cmd_remove() {
  local path="${1:-}"
  [ -n "$path" ] || die "usage: worktree.sh remove PATH"
  case "$path" in */pr-review-watch/*-pr-[0-9]*) ;; *) die "refusing to remove $path: not a pr-review-watch worktree" ;; esac
  [ -e "$path" ] || { echo "already gone: $path" >&2; return 0; }

  local common
  common="$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || die "$path is not a git worktree"
  git --git-dir="$common" worktree remove --force "$path"
  git --git-dir="$common" worktree prune
  git --git-dir="$common" update-ref -d "refs/pr-review-watch/pr-${path##*-}" 2>/dev/null || true
}

case "${1:-}" in
  add) shift; cmd_add "$@" ;;
  remove) shift; cmd_remove "$@" ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
