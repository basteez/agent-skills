#!/usr/bin/env bash
# List open pull requests that are waiting for the authenticated user's review
# and have not been handed out yet. Prints one JSON object per line:
#   {"repo":"owner/name","number":12,"title":"...","url":"...","author":"...",
#    "headSha":"...","baseRef":"main"}
#
# A PR is keyed by repo, number and head commit, so a re-request after new
# pushes is reported again while a PR already under review is not.
#
# Usage:
#   pending-reviews.sh [options] OWNER/REPO [OWNER/REPO ...]
#
# Options:
#   --interval N     Keep running, checking every N seconds (watch mode).
#                    Without it the script checks once and exits.
#   --state FILE     Where reported PRs are remembered. In watch mode the default
#                    is a temporary file deleted on exit, so every watch starts
#                    clean. A one-shot check has no memory unless you pass this:
#                    create one file per session and pass it to every check.
#   --user-only      Only PRs requesting you personally, not one of your teams.
#   --include-drafts Also report draft PRs (skipped by default).
#   --forget KEY     Remove one key (owner/repo#N@sha) from the state file given
#                    with --state, so a PR whose review failed is reported again,
#                    then exit.
set -uo pipefail

interval=""
state=""
qualifier="review-requested"
drafts="false"
forget=""
repos=()

while [ $# -gt 0 ]; do
  case "$1" in
    --interval) interval="${2:-}"; shift 2 ;;
    --state) state="${2:-}"; shift 2 ;;
    --user-only) qualifier="user-review-requested"; shift ;;
    --include-drafts) drafts="true"; shift ;;
    --forget) forget="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) repos+=("$1"); shift ;;
  esac
done

if [ -n "$forget" ]; then
  [ -n "$state" ] || { echo "--forget needs --state" >&2; exit 2; }
  tmp="$(mktemp)"
  grep -vxF -- "$forget" "$state" > "$tmp" || true
  mv "$tmp" "$state"
  exit 0
fi

[ "${#repos[@]}" -gt 0 ] || { echo "no repositories given" >&2; exit 2; }
command -v gh >/dev/null || { echo "gh CLI not found" >&2; exit 2; }

# State only has to live as long as the session: GitHub drops the review
# request once a review is submitted, so a PR still pending at the next start
# was never reviewed and must be reported again.
if [ -z "$state" ]; then
  state="$(mktemp "${TMPDIR:-/tmp}/pr-review-watch-seen.XXXXXX")"
  trap 'rm -f "$state"' EXIT
  trap 'exit 130' INT TERM
else
  mkdir -p "$(dirname "$state")" && touch "$state"
fi

check_once() {
  local query=("is:pr" "is:open" "$qualifier:@me" "archived:false")
  [ "$drafts" = "true" ] || query+=("draft:false")
  # gh sends the query as GitHub advanced search, where qualifiers separated by
  # a space are ANDed: "repo:a/x repo:b/y" matches nothing as soon as two repos
  # are watched. Group them as "(repo:a/x OR repo:b/y)". Each word is its own
  # argument because gh quotes any argument containing a space, which GitHub
  # then rejects as invalid syntax.
  local r last=$((${#repos[@]} - 1)) i=0 term
  for r in "${repos[@]}"; do
    term="repo:$r"
    [ "$i" -eq 0 ] && term="($term"
    [ "$i" -eq "$last" ] && term="$term)"
    [ "$i" -eq 0 ] || query+=("OR")
    query+=("$term")
    i=$((i + 1))
  done

  local found
  if ! found="$(gh search prs "${query[@]}" --limit 100 \
      --json number,repository \
      --jq '.[] | "\(.repository.nameWithOwner) \(.number)"' 2>&1)"; then
    echo "search failed: $found" >&2
    return 1
  fi

  local repo num line key
  while read -r repo num; do
    [ -n "$repo" ] || continue
    if ! line="$(gh pr view "$num" -R "$repo" \
        --json number,title,url,author,headRefOid,baseRefName \
        --jq "{repo: \"$repo\", number, title, url, author: .author.login, headSha: .headRefOid, baseRef: .baseRefName} | tojson" 2>&1)"; then
      echo "could not read $repo#$num: $line" >&2
      continue
    fi
    key="$repo#$num@$(printf '%s' "$line" | sed -n 's/.*"headSha":"\([0-9a-f]*\)".*/\1/p')"
    grep -qxF -- "$key" "$state" && continue
    printf '%s\n' "$key" >> "$state"
    printf '%s\n' "$line"
  done <<< "$found"
}

if [ -z "$interval" ]; then
  check_once
  exit $?
fi

case "$interval" in ''|*[!0-9]*) echo "--interval needs a number of seconds" >&2; exit 2 ;; esac
while :; do
  check_once || true
  sleep "$interval"
done
