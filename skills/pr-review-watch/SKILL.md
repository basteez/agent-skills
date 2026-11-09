---
name: pr-review-watch
description: Watch one or more GitHub repositories for pull requests that request the user's review, and review each one as it arrives in an isolated worktree through a subagent, then approve or request changes on GitHub without modifying any file. Uses the BMAD code review when installed, otherwise another installed code-review skill, otherwise a plain review. Use this whenever the user asks to poll, watch, monitor or keep an eye on PRs awaiting their review, wants review requests handled automatically, says things like "review my incoming PRs", "tieni d'occhio le PR da revisionare", or names repos to watch for review requests. With no repo named, it watches the repository of the current project.
metadata:
  summary: "Polls GitHub for PRs that request your review and reviews each one in a throwaway worktree via a subagent, then approves or requests changes."
---

# PR review watch

Keep a poll running on GitHub for pull requests that request the user's review. For each new one,
check it out in a throwaway worktree, review it in a subagent, submit an approval or a request
for changes, remove the worktree, and record what happened. The main conversation stays a thin
dispatcher: the diff, the review reasoning and the tool noise all live in the subagent.

**What this skill must never do.** It does not edit, commit or push to any PR, does not run the
review skill's "fix" or "apply" mode, does not merge, close or dismiss anything, and does not
touch the user's own checkout or current branch. Its only outward action is one review per PR
(approve or request changes). A review is visible to the PR author and everyone watching the
repository, so a wrong one costs the user credibility; when in doubt, request changes with a
clear question rather than approve.

The two helper scripts live next to this file, in `scripts/`. Resolve their absolute path from
the location of this `SKILL.md` and call them by that path.

## Step 1 — Settle the parameters

**Repositories.** Use the repositories the user named, in `OWNER/REPO` form. If they named none,
use the current project's repository:

```bash
gh repo view --json nameWithOwner --jq .nameWithOwner
```

If the current project is a fork, `gh repo view` returns the fork. Review requests normally arrive
on the upstream repository, so check `gh repo view --json parent` and ask the user which one they
mean if a parent exists. If the session is not inside a GitHub repository and no repo was named,
ask; do not guess.

**Interval.** Default to 60 seconds. Accept whatever the user asks for, but not below 30: the
search API allows 30 requests a minute and each cycle spends one, plus one per new PR.

**Who counts as "me".** By default, requests addressed to one of the user's teams count too. If
the user only wants PRs that name them personally, pass `--user-only` to the poll script.

**Where to record reviews.** If the user named a destination (a Logseq journal, a notes file, an
issue tracker), use it. If their memory or project instructions already describe a work log and
how to write to it (a helper script, an API), use that mechanism exactly. Otherwise keep a
running list in the conversation and tell the user at the start that this is where it goes.

Check prerequisites once before starting: `gh auth status` must succeed, and the account must
have at least read access to every watched repository. Report a failure instead of starting a
poll that will fail every minute.

State the plan back in two or three lines (repos, interval, review method from Step 3, log
destination) and start. Do not wait for confirmation unless something above was ambiguous.

## Step 2 — Poll

`scripts/pending-reviews.sh` does the GitHub query and the bookkeeping. It prints one JSON line per
PR that requests the user's review and has not been reported before, and remembers each PR by
repository, number and head commit. A PR still under review is not reported twice; a PR that is
re-requested after new pushes is reported again, which is what the user wants. The first check runs
immediately, so PRs already waiting when the watch starts are reported too.

That memory lasts for one session only. GitHub removes the review request once a review is
submitted, so a PR that is still pending when a new session starts was never reviewed (the
previous session ended or failed mid-way) and has to be picked up again. Create the state file
once at the start of the session and pass it to every call, so a failed review can be forgotten
later:

```bash
STATE="$(mktemp "${TMPDIR:-/tmp}/pr-review-watch-seen.XXXXXX")"
scripts/pending-reviews.sh --state "$STATE" --interval 60 OWNER/REPO [OWNER/REPO ...]   # watch mode, runs until stopped
scripts/pending-reviews.sh --state "$STATE" OWNER/REPO [OWNER/REPO ...]                 # one check, then exit
```

Never reuse a state file from an earlier session. Without `--state`, watch mode uses its own
temporary file and a one-shot check remembers nothing, so it reports every pending PR each time.

Use the best recurring mechanism the agent has, in this order:

1. A tool that runs a long-lived command in the background and wakes you on each line of output
   (in Claude Code, the Monitor tool). Run the script in watch mode under it. This is the
   cheapest option: you are only woken when there is something to review.
2. A scheduler that re-runs a prompt on an interval (in Claude Code, `/loop` or a cron tool).
   Schedule the one-shot form of the script.
3. Neither. Run one check now, review what it finds, and tell the user that this agent cannot
   poll unattended, so they need to ask again or use an agent that can.

Draft PRs are skipped by default; pass `--include-drafts` if the user wants them. Errors from
GitHub go to stderr and the watch keeps running. If the same error repeats for several cycles
(expired auth, lost access), tell the user rather than letting it fail silently.

## Step 3 — Pick the review method

Decide once, at start-up, and say which you picked. Re-check per PR only for the BMAD case below,
because BMAD is installed per project and the PR's repository may have it while the current one
does not.

1. **BMAD.** If a skill named `bmad-code-review` is available to you, use it. If it is not in your
   skill list, look for it inside the PR's worktree once it exists (for example
   `.claude/skills/bmad-code-review/SKILL.md`, `.agents/skills/bmad-code-review/SKILL.md`, or
   under `_bmad/`). If it is there, the subagent reads that file and follows it directly.
2. **Another code-review skill.** Otherwise look through your available skills for one whose name
   or description says it reviews code or pull requests (for example `code-review`,
   `review-pr`, `pr-review`). Prefer one aimed at correctness over pure style. Skip any skill
   whose only mode is to change code.
3. **No skill.** Otherwise the subagent reviews on its own, following the checklist in Step 4.

Whatever skill is used, its output has to fit this skill's contract: findings only, no edits.
Many review skills offer to fix what they find, post inline comments, or apply changes after
the review. Tell the subagent explicitly to decline those steps and to run only the
read-and-report part. If a skill takes flags, never pass a fix or apply flag.

## Step 4 — Review each PR

For each JSON line from the poll, in order of arrival. Reviews may run in parallel if the agent
supports it, but cap concurrency at two or three so they do not compete for rate limit.

**Create the worktree** from the main conversation, not inside the subagent, so cleanup is
guaranteed even if the subagent fails:

```bash
scripts/worktree.sh add OWNER/REPO NUMBER    # prints the worktree path
```

The script uses the current checkout if one of its remotes points at the repository, otherwise a
cache clone it creates on first use. The worktree is detached at the PR head under the temp
directory, so the user's branches and working tree are never touched. If the user keeps clones of
the watched repositories in known places, pass `--clone DIR` to reuse them.

**Hand the review to a subagent.** Use the agent's subagent mechanism (in Claude Code, the Agent
tool) so the diff never enters the main context. If the agent has no subagents, run the review
inline and keep your summary to the main conversation short. Give the subagent a self-contained
brief, since it has none of this conversation:

- the worktree path (its working directory), repository, PR number, URL, title, author, base
  branch and head SHA;
- the review method from Step 3 and how to invoke it;
- the hard rules: read only, no file edits, no commits, no pushes, no fix modes, no inline
  comments, no other GitHub actions;
- what it must return: a verdict of APPROVE or REQUEST_CHANGES, and a review body.

For the no-skill case, include this checklist in the brief: read the PR description and linked
issue; read the diff against the base (`git diff origin/BASE...HEAD` in the worktree, or `gh pr
diff`); read enough surrounding code to judge each change; look for correctness bugs, missing
error handling, security problems, broken contracts with callers, and missing or wrong tests;
run the project's existing tests or linters only if they run locally without network or secrets
and without writing outside the worktree. Approve when nothing would block a merge; request
changes when at least one finding would.

The review body should name each blocking finding with file and line and say why it matters,
then list non-blocking suggestions separately. Write it in English, whatever language the
conversation is in, unless the user asks for a different one: the review is read by the PR author
and the team, not by the user who started the watch.

**Submit the review** from the main conversation using the subagent's verdict and body:

```bash
gh pr review NUMBER -R OWNER/REPO --approve --body-file BODY_FILE
gh pr review NUMBER -R OWNER/REPO --request-changes --body-file BODY_FILE
```

Write the body to a file in the temp directory first; a body passed inline breaks on quotes and
backticks. Submitting from the main conversation rather than the subagent keeps the one outward
action in a place you control. If the head SHA changed while the review ran, do not submit: the
review would describe code that is no longer the PR. Forget the PR (below) so the next cycle
picks up the new head.

**Remove the worktree**, whether the review succeeded or not:

```bash
scripts/worktree.sh remove WORKTREE_PATH
```

**If the review failed** (subagent error, unreadable diff, `gh pr review` rejected), do not retry
in a loop. Tell the user, and make the PR eligible again only if they want it retried:

```bash
scripts/pending-reviews.sh --state "$STATE" --forget 'OWNER/REPO#NUMBER@HEAD_SHA'
```

## Step 5 — Record it

After each PR, write one entry to the destination chosen in Step 1, containing the time, the
repository and PR number with its URL, the title, the author, the verdict, and one line on the
main reason. Follow the destination's own conventions if the user's instructions define them
(language, format, link style). If writing the entry fails, say so in the conversation; a gap in
the user's log that nobody noticed is worse than an error message.

Then post a one-line note in the main conversation, for example:
`APPROVE  acme/api#412  "Add retry to webhook sender"  (bob) · no blocking issues`

## Stopping

Stop when the user asks. Stop the background watch or the scheduled job, remove any worktree
still under the temp `pr-review-watch` directory with `scripts/worktree.sh remove`, delete the
session's state file (`rm -f "$STATE"`), and give a
short tally of the PRs reviewed in this session with their verdicts.
