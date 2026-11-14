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

**Ask first. Do not assume a PR.** Not every change earns a document, and a ceremony
applied to work that does not need it is how a gate stops being taken seriously. Put the
question with AskUserQuestion, recommending one:

| Option | Fits | Cost |
| --- | --- | --- |
| **ADR as a docs-only PR** | New architecture, a pattern others will copy, anything contested, anything you will be asked to justify in six months | A review round before any code |
| **ADR in this thread** | A real decision with a contained blast radius — you want it stated and agreed, not filed | One message, approved inline |
| **Skip the ADR** | The approach is obvious, the pattern already exists in the codebase, and the audit found no conflicts | Nothing — go straight to `plan` |

Recommend **PR** when the audit found a rule conflict, no existing pattern to follow, or
a backend contract that does not exist yet. Recommend **skip** when the audit found a
directly comparable feature merged recently and nothing contradicts it.

Record the answer — it changes what `run.sh next` returns:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/run.sh adr pr       # or: thread, or: skip
```

Skipping the ADR does not skip the *decision*. State the approach, the reuse verdicts and
the assumptions in the thread anyway, in a few lines. What you are skipping is the file
and the review round, not the thinking — and if the thread version turns out to be
contested, promote it to a PR rather than arguing in chat.

#### If the answer was `pr`

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

#### If the answer was `thread`

Post the same content as a message: context, the options weighed, the recommendation, the
reuse verdicts, and the gaps with the assumption taken for each. Then stop and wait for
approval here. No branch, no file, no PR. On approval:
`run.sh gate adr approved "approved in thread"`.

#### If the answer was `skip`

State the approach and the assumptions in two or three lines, then go straight to `plan`.
`run.sh adr skip` already removed the phase from the sequence.

On resumption:

```bash
gh pr view <N> --comments
gh api repos/{owner}/{repo}/pulls/<N>/comments        # inline review threads
```

Revise the ADR against every comment and push. Reply to each thread saying what changed,
or why you disagree — a comment silently ignored is the failure mode this gate exists to
prevent. Iterate until the PR is approved or merged. **Approval is the signal.** Record
it: `run.sh gate adr approved "<PR url>"`.

Every comment on this PR is also training data — hand them to `/talview-learn:learn` at the end
of the run.

### plan
`writing-plans` + `stack-planning`. Decompose into stacked PRs, one per sub-issue, each
independently reviewable and shippable. Backend-blocked work becomes its own tracked
item. Create Linear sub-issues with `issue-management`.

Once the human has agreed how many PRs the stack is, record it:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/run.sh stack init <count>
```

That number is a commitment to stop between each one. See **One PR at a time** below.

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
`/talview-verify:verify-browser`. Drive the real UI and produce evidence, not assurances.

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

### ship — **one PR at a time**

`finishing-branch` + `gh stack submit`. The push gate verifies before anything leaves the
machine: artifacts complete, lint/typecheck/test green and not stale.

Then the stack hold, which is not optional and not yours to decide:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/run.sh stack pushed "<pr url>"
LESSON="$(dirname "${CLAUDE_PLUGIN_ROOT}")/talview-learn/scripts/lesson.sh"
"$LESSON" queue add "<pr url>"
```

`stack pushed` arms a gate that denies `gh pr create`, `gh stack submit`, `git checkout -b`
and `git worktree add` until a person clears it. **Say the PR is up, say which number it
is, and stop.** Do not start the next one. Do not offer to start the next one.

While the hold is on, your job is this PR and nothing else:

- Answer every review thread. Changed something? Say what. Disagree? Say why.
- Commit and push fixes to the **same branch** — both are still allowed.
- If the human pushes back **in this session** rather than on the PR, capture it the
  moment it is resolved. That exchange exists nowhere else:

  ```bash
  "$LESSON" capture <slug> adopted  "<what they argued, one line>"
  "$LESSON" capture <slug> rejected "<what they argued, and why it did not hold>"
  ```

  Capture `rejected` too. Being overruled and being right are different lessons, and a
  ledger that only records the human winning teaches the wrong thing.

When they say go, they clear it: `run.sh stack next`. Only then start PR N+1.

#### Committing

Bound the commit in time — use the agent harness's own command timeout, since GNU
`timeout(1)` is not present on a stock macOS. If the commit **fails for any reason, or
runs past ~30 seconds**, stop there:

- Print the full commit message in a copyable block, plus whatever the hook printed.
- Say what happened. Do not retry, do not wait it out, do not reduce the scope to get
  past it, and never `--no-verify`.
- The human commits it. Only once they confirm it landed may you push or open the PR.

The hooks in this workspace are slow and can fail on pre-existing problems that have
nothing to do with this change. What to do about that — fix it, split the commit, commit
by hand — is the human's call, and it is a call they can only make while the message and
the hook output are in front of them. A silent retry hides the decision; a blocked turn
hides it for longer.

A failed or timed-out commit is never followed by a push.

Never `gh pr merge`. Merging is a human action.

### learn

Two things happen here, and only one of them is harvesting.

**Harvest the ADR PR now.** Its gate waited for review, so its threads — including
anything you pushed back on — exist and are fresh. `/talview-learn:learn` over it.

**Queue the code PRs.** They are minutes old and have no review yet; harvesting them now
would learn nothing. Record them so the review is not lost when it arrives:

```bash
LESSON="$(dirname "${CLAUDE_PLUGIN_ROOT}")/talview-learn/scripts/lesson.sh"
"$LESSON" queue add "<pr url>"
```

The SessionStart hook will name any queued PR still owing a harvest, so the next session
that touches this branch picks it up. Do not close the run by claiming the feedback loop
ran — it has not run yet, and saying so is the difference between a loop and a ritual.

### concepts

`/tlv:concept`. At most three, drawn from what the run used non-trivially, what review
flagged, or what cost real time. Not only React and not only frontend — a shell gate, an
RxDB migration, an ICU rule or a CI failure all count.

Routine work that taught nothing produces nothing. Say that rather than padding: a
library that fills with filler stops being read.

```bash
LEARN="$(dirname "${CLAUDE_PLUGIN_ROOT}")/talview-learn/scripts"
"$LEARN"/journal.sh set "<id>" summary "<what shipped, two lines>"
"$LEARN"/concept.sh add <slug> --entry "<id>" --tags "..." --title "..."   # body on stdin
```

The journal entry already exists — `run.sh start` created it. The id is in the run state
under `journalEntry`.

## Standing constraints

- The target repo is modified **only** through the work itself. No config changes, no
  lint-rule changes, no unrelated fixes. Pre-existing failures stay as they are; note
  them, do not adopt them.
- Agent state lives in `~/.talview/<repo>/runs/`, never in the product repo.
- One gate. If you find yourself wanting a second, write the question into the ADR
  instead and let the existing gate carry it.
