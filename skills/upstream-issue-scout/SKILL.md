---
name: upstream-issue-scout
description: Scout the upstream repository of a fork for open issues that are genuinely available to pick up (unassigned, unclaimed, no linked PR, still relevant) and rank them by value-to-maintainers times tractability-for-one-contributor. Use this whenever the user is inside a fork and asks what they could contribute upstream, wants to find an issue worth working on, asks to check or triage upstream issues, mentions opening a PR to the project they forked, or wants candidates vetted for feasibility before any code gets written. Works with any GitHub project regardless of its label taxonomy or contribution process.
---

# Upstream Issue Scout

The current repository is a fork. The job is to come back with a short, ranked list of upstream
issues the user could realistically land a PR for, with enough evidence attached that they can
pick one in a couple of minutes instead of reading a hundred issue threads.

The hard part is not finding open issues. It is filtering out the ones that look available but
aren't: somebody quietly opened a draft PR, a maintainer promised it to a newcomer four days ago,
or the thread is a two-year API design argument wearing a bug label. Everything below is built
around that filter.

**This skill stops at the shortlist.** It never comments on an issue, never self-assigns, never
opens a PR. Those are the user's calls, and claiming work you might not finish is rude upstream.

## Prerequisites

Check these before starting; if something is missing, say so and ask rather than guessing.

```bash
gh auth status                      # authenticated gh CLI
gh api rate_limit --jq '.rate'      # need a few hundred calls of headroom for the deep dive
```

## Step 1 — Resolve the upstream repository

Do not assume a remote named `upstream` exists. Resolve in this order:

```bash
git remote -v                                        # look for an 'upstream' remote
gh repo view --json nameWithOwner,isFork,parent      # 'parent' is the authoritative answer
```

`gh repo view` reads the fork relationship from GitHub itself, so it works even when the only
remote is `origin`. If the repo is not a fork and no upstream remote exists, stop and ask which
repository to scout.

If the `upstream` remote is missing, mention it and offer to add it, but don't do it silently:

```bash
git remote add upstream https://github.com/OWNER/REPO.git && git fetch upstream
```

Also note how far behind the fork is (`git rev-list --count HEAD..upstream/<default-branch>`) —
a fork that is thousands of commits behind changes the advice, because file paths and code in
the local checkout may no longer match what the issue describes.

## Step 2 — Learn this project's contribution rules

This is what keeps the skill generic. Never hardcode label names. Read the project first:

```bash
gh api repos/OWNER/REPO/contents/CONTRIBUTING.md --jq '.content' | base64 -d | head -200
# also try .github/CONTRIBUTING.md, docs/CONTRIBUTING.md, CONTRIBUTING.adoc, CONTRIBUTING.rst
gh label list --repo OWNER/REPO --limit 300
```

From CONTRIBUTING, extract: how contributors claim work (comment? `/assign`? just open a PR?),
whether a CLA or DCO sign-off is required, which branch PRs target, and any rule about not
opening PRs for untriaged issues. Projects differ sharply here and getting it wrong wastes the
user's work.

Then bucket the actual labels by **intent**, matching case-insensitively on substrings so the
same logic works across taxonomies:

| Bucket | Typical substrings | Meaning |
|---|---|---|
| Invitation | `good first issue`, `help wanted`, `up-for-grabs`, `ideal-for-contribution`, `contributions welcome`, `e-easy`, `beginner` | Maintainers explicitly want outside PRs |
| Accepted | `bug`, `confirmed`, `verified`, `accepted`, `triaged`, `regression`, `documentation`, `chore` | Work is agreed to exist |
| Warning | `needs design`, `discussion`, `rfc`, `proposal`, `on hold`, `blocked`, `waiting-for-triage`, `needs-info`, `needs-reproduction`, `breaking change`, `epic`, `meta` | Not settled, or too big |

Report which buckets this project actually populates. A repo with no invitation labels at all is
a signal in itself: lean harder on maintainer comments as the intent signal.

Finally, pick up local conventions from the checkout — `AGENTS.md`, `CLAUDE.md`, `README`, or a
project-context doc the user points at — so the shortlist can reference real module paths and the
real build/verify commands.

## Step 3 — Harvest candidates

Let GitHub's search do the coarse filtering. `no:assignee` and `-linked:pr` are supported
qualifiers and they remove most of the noise in one shot:

```bash
CUTOFF=$(date -d '6 months ago' +%Y-%m-%d)   # macOS: date -v-6m +%Y-%m-%d

gh issue list --repo OWNER/REPO --state open --limit 60 \
  --search "no:assignee -linked:pr updated:>=$CUTOFF sort:updated-desc" \
  --json number,title,labels,milestone,comments,createdAt,updatedAt,url
```

Run this two or three times with different slices rather than one giant query:

1. Invitation-labelled issues (the highest-yield slice, if the project has such labels).
2. Accepted-bucket issues with low comment counts (`comments:<8`) — small, uncontested work.
3. Documentation and test-coverage issues, which are almost always tractable and almost always
   welcome.

Widen the window to ~12 months only if the harvest comes back thin. Aim for 20-40 raw candidates
before filtering; more than that and the deep dive gets expensive for no benefit.

## Step 4 — Claim detection

`no:assignee -linked:pr` is necessary but not sufficient. GitHub only links a PR when someone
writes `Fixes #123`, and plenty of in-flight work is invisible to that qualifier. For each
surviving candidate, check the timeline and the last stretch of comments:

```bash
gh api repos/OWNER/REPO/issues/NUM/timeline --paginate \
  --jq '.[] | select(.event=="cross-referenced" or .event=="connected" or .event=="assigned")
        | {event, when:(.created_at), src:(.source.issue.html_url // .assignee.login)}'

gh issue view NUM --repo OWNER/REPO --comments
```

Classify each into one of four states:

- **FREE** — no assignee, no referencing PR, no claim language in comments. Keep.
- **SOFT-CLAIMED (stale)** — someone said they'd take it, but more than ~60 days ago with no PR
  and no follow-up. Keep, flagged: the polite move is to ask on the thread before starting.
- **CLAIMED** — claim language ("I'll take this", "working on it", "/assign", "can I try this")
  within the last ~60 days. Drop.
- **PR OPEN** — a cross-referenced PR exists and is open, including drafts. Drop.

Cross-referenced PRs that were *closed unmerged* are worth a second look rather than an automatic
drop: they often mean the fix was attempted and rejected, and reading why is the cheapest possible
lesson about that project's standards.

## Step 5 — Deep-dive the survivors

Cap this at the 12-15 strongest survivors. For each, work out:

- **What is actually being asked.** Distinguish the reported symptom from the fix maintainers
  want. If the thread never converges on a fix, that is a finding, not a gap in the research.
- **Maintainer intent.** Milestone assignment, an invitation label applied by a maintainer, or a
  maintainer comment sketching the approach. Weight *recent* maintainer engagement heavily; an
  invitation label applied in 2021 has decayed.
- **Where it lands in this fork.** Grep the local checkout for the classes, files, or symbols
  named in the thread and give a real path. This is the difference between a report the user
  trusts and a list of links they have to re-research.
- **Blast radius.** Rough count of files and modules likely touched, whether public API is
  involved, and whether tests exist nearby to extend.
- **Verification cost.** Can this be tested locally with the project's normal build, or does it
  need integration infrastructure the user probably doesn't have?

## Step 6 — Score and rank

Score each survivor on two axes, 1-5, and rank by the product. Show the numbers so the user can
disagree with the ranking rather than having to trust it.

**Value to upstream**
| | |
|---|---|
| 5 | Milestoned, or a maintainer has explicitly asked for a PR |
| 4 | Invitation label plus recent maintainer engagement |
| 3 | Confirmed bug or accepted docs gap, no explicit invitation |
| 2 | Plausible improvement, no maintainer signal |
| 1 | Unvalidated feature request |

**Tractability for one contributor**
| | |
|---|---|
| 5 | Single file or module, reproduction provided, obvious test hook |
| 4 | Single module, approach agreed in the thread |
| 3 | Couple of modules, or the approach needs a design decision the user can make alone |
| 2 | Cross-module, or requires infrastructure to verify |
| 1 | Needs maintainer buy-in on API shape before any code is worth writing |

Break ties by smaller blast radius. A 20-line fix that merges beats a 400-line fix that stalls in
review for three months.

## Step 7 — Flag the traps

Call these out explicitly, even on issues that score well. They are the main way a contributor
burns a weekend for nothing:

- **Design debate in disguise** — long thread, several competing proposals, no maintainer verdict.
- **Cross-module churn** — the honest fix touches shared abstractions many modules depend on.
- **Stale consensus** — the agreed approach is old enough that the codebase has moved past it.
- **Untriaged** — the project's own rules say don't PR before triage, and this one isn't triaged.
- **Ownership** — the area has a de facto owner who reworks outside patches.
- **Process cost** — CLA, DCO sign-off, a required issue-first workflow, or PRs that must target
  a maintenance branch rather than the default one.
- **Silent repo** — no maintainer activity anywhere in months; the PR may simply never be reviewed.

## Report format

Use this structure:

```markdown
# Upstream scouting report — OWNER/REPO
Fork: <origin> · Upstream: <parent> · Fork is N commits behind <branch> · <date>
Scanned <X> open issues, <Y> passed the claim filter.

## Contribution rules picked up
<claiming convention, CLA/DCO, target branch, label buckets this project uses>

## Shortlist
| Rank | Issue | Title | Area in fork | Claim | Value | Tract. | Score | Blast |
|------|-------|-------|--------------|-------|-------|--------|-------|-------|

## Candidates in detail
### #NNN — <title>   [score]
- **Ask:** what maintainers actually want changed
- **Evidence of intent:** milestone / labels / who said what, with dates
- **Where it lands here:** real paths in this checkout
- **Blast radius:** files, modules, public API yes/no, test surface
- **Claim status:** FREE | SOFT-CLAIMED (stale, since <date>)
- **Traps:** or "none spotted"
- **First move:** the single concrete next action

## Dropped, and why
<one line each — claimed, PR open, design debate. Useful so the same issues aren't re-scouted.>

## Recommendation
<one pick, one sentence of why, and what to do before writing code>
```

## Handoff

After the shortlist, ask which candidate to pursue. Then hand off to whatever implementation
workflow the repo or the user already has (an agent pipeline, a spec workflow, plain
implementation) rather than inventing one — check for local workflow docs before assuming.

Whatever the path, three things carry over from the scouting phase into the work:

- The project's own verify command (formatter, linter, static analysis, tests) has to pass
  locally before pushing. Find it in CONTRIBUTING or the build config, not from memory.
- The sign-off requirement, if there is one, applies to every commit.
- If the user wants a PR description, write it in plain prose as a human would: what was broken,
  what changed, how it was verified. No em dashes, no bullet-point theatre, no emoji.

## Guardrails

- Read-only against upstream. No comments, no assignment, no PR creation, no reactions.
- Never invent an issue number, a label, or a maintainer quote. Every claim in the report traces
  to something fetched. If a check couldn't run, say so instead of filling the gap.
- Respect the API budget: prefer one search over ten, and cap the deep dive.
- If the harvest turns up nothing viable, say that plainly and suggest widening the window or
  looking at a docs or test-coverage slice. A padded shortlist is worse than a short one.
