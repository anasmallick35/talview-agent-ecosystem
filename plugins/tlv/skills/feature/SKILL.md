---
name: feature
description: The feature delivery track. Carries a feature ticket from audit through an ADR you review, then autonomously to an open PR — decomposition, stacked branches, implementation, tests, stories, e2e, browser verification and self-review. Use after /tlv:start classifies a run as a feature.
---

# Feature track

One human gate: the ADR. Everything before it is evidence-gathering; everything after it
is execution. Your job is to make the gate worth stopping at and then not need a second
one.

Resolve each phase's tooling with
`"${CLAUDE_PLUGIN_ROOT}"/scripts/skill-map.sh phase <name>` and invoke what it names.
Advance with `run.sh phase <name>` — that is what arms and disarms the gates.

## Phase sequence

### audit
`/tlv:audit`. Produces the audit document. Do not proceed without reuse verdicts.

### brainstorm
Invoke the workspace `brainstorming` skill. Two to four distinct approaches weighed
against the CLAUDE.md priority order (accessibility > UX > performance > maintainability
> speed), converging on one recommendation. Mandatory for anything non-trivial — this is
a CLAUDE.md hard rule, not a suggestion.

### adr — **the gate**

Write the ADR with the workspace `adr-author` skill into `docs/adr/`, numbered after the
highest existing file. Prose follows `factual-terse`.

The ADR must carry, from the audit: the reuse verdicts, the pattern being followed and
why, every rule conflict found, the design source, the backend status and contract, and
**the gaps with the assumption taken for each**. An ADR that reads as though nothing was
uncertain is a failed ADR.

Then open a docs-only PR:

```bash
git checkout -b <ticket>-adr
git add docs/adr/NNNN-*.md && git commit
gh pr create --draft=false --title "docs(adr): NNNN <title>" --body "<summary + the open questions, listed>"
```

**Stop here.** Say the PR is open and that you are waiting on review. Do not start
implementation, do not create sub-issues, do not branch further.

On resumption:

```bash
gh pr view <N> --comments
gh api repos/{owner}/{repo}/pulls/<N>/comments        # inline review threads
```

Revise the ADR against every comment and push. Reply to each thread saying what changed,
or why you disagree — a comment silently ignored is the failure mode this gate exists to
prevent. Iterate until the PR is approved or merged. **Approval is the signal.** Record
it: `run.sh gate adr approved "<PR url>"`.

Every comment on this PR is also training data — hand them to `/tlv:learn` at the end
of the run.

### plan
`writing-plans` + `stack-planning`. Decompose into stacked PRs, one per sub-issue, each
independently reviewable and shippable. Backend-blocked work becomes its own tracked
item. Create Linear sub-issues with `issue-management`.

### branch → implement_* → i18n → telemetry
Per stack: `git-workflows` / `worktree-setup`, then the phase skills. Keep
`run.sh phase` in step with what you are actually doing — gates stay idle through
`implement_*`, so this is where you build freely.

Hard rules that the linter will not always catch for you: no cross-module imports; no ID
fallback chains; Teserra for all interactive UI and typography; `@packages/logger` never
`console.*`; every user-facing string internationalised in every locale file. The
edit-time lint hook reports what it can — CLAUDE.md is broader than the lint config, and
the difference is yours to hold.

### test_unit → test_stories → test_e2e → a11y
**Gates arm here.** From this point the Stop hook refuses to end a turn while a changed
component lacks a test, a component lacks a story, a new page lacks a Cypress spec, or a
locale key this branch added is missing from a sibling locale file.

Write them because they are the deliverable, not to satisfy the gate. Cypress specs
cover all ten branches named in CLAUDE.md. If an obligation genuinely does not apply,
waive it with a reason — `run.sh waive <key> "<reason>"` — and expect the reason to be
read.

### verify_browser
`/tlv:verify-browser`. Drive the real UI and produce evidence, not assurances.

### self_review
`code-review` (Trigger B, local pre-PR) plus `react-code-quality`. Then
`verification-before-completion`: every claim of "works" needs command output behind it.

Record what actually passed:

```bash
EV="$(dirname "${CLAUDE_PLUGIN_ROOT}")/talview-core/scripts/evidence.sh"
"$EV" record lint      pass 'pnpm exec turbo run lint --filter=...'
"$EV" record typecheck pass '...'
"$EV" record test      pass '...'
```

Record `pass` only for a command you ran and watched succeed. The push gate compares
each timestamp against the newest source edit, so a pass recorded ahead of the work is
not merely dishonest — it expires the moment you touch a file, and blocks you anyway.

### ship
`finishing-branch` + `gh stack submit`. The push gate verifies before anything leaves the
machine: artifacts complete, lint/typecheck/test green and not stale. It replaces the
per-push confirmation, which is why it is strict.

Never `gh pr merge`. Merging is a human action.

### learn
`/tlv:learn` over the ADR PR comments and the code PR comments.

## Standing constraints

- The target repo is modified **only** through the work itself. No config changes, no
  lint-rule changes, no unrelated fixes. Pre-existing failures stay as they are; note
  them, do not adopt them.
- Agent state lives in `~/.talview/<repo>/runs/`, never in the product repo.
- One gate. If you find yourself wanting a second, write the question into the ADR
  instead and let the existing gate carry it.
