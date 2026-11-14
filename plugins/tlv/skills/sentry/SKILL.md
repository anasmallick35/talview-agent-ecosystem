---
name: sentry
description: The Sentry triage track. Pulls an issue, verifies its frames against the real code, and presents a verdict for you to confirm — fix, file, snooze or close. Use after /tlv:start classifies a run as a Sentry issue.
---

# Sentry track

The gate here is the **verdict**, and it is the whole point of the track. Most Sentry
issues should not become code changes; deciding which ones should is the judgment being
asked for. Your job is to make that decision cheap and well-evidenced.

Project: `v8-recruit` (id 252) on `sentry.talview.com`, org `talview`. Use the workspace
`sentry-triage` skill for a single issue and `sentry-investigation` for a sweep.

## 1. Pull the issue

Via the Sentry MCP: stack trace, breadcrumbs, tags, first and last seen, event and user
counts, affected releases, and a replay if one exists.

Note the shape of the volume, not just its size. A hundred events from one user is a data
problem; a hundred events from a hundred users is a code problem. Something that stopped
three releases ago is already fixed.

## 2. Verify the frames against the code

**This is the step that makes the verdict trustworthy.** Open every app frame in the
stack and check the line is still what Sentry thinks it is. Minified or stale-sourcemap
traces routinely point at code that has since moved.

Establish:

- Does the named file and line still exist, and still do that?
- Is the failure reachable on the current `develop`, or already fixed?
- Is it ours? Browser-extension noise, cancelled requests, `ResizeObserver` loop
  warnings and offline network errors are not defects.
- What is the user-visible consequence — a crashed page, a silent no-op, or nothing at
  all?

An unreachable or third-party frame changes the verdict. Say so rather than proposing a
defensive fix for something that cannot happen.

## 3. Verdict — **the gate**

Present one recommendation with its evidence, and the alternatives you rejected:

| Verdict | When |
| --- | --- |
| **fix** | Reachable on current code, ours, real user impact. Continue the track. |
| **file** | Real but out of scope now, or the cause is backend. Create a Linear bug with the full analysis and link it. |
| **snooze** | Real but low impact, or gated behind something already scheduled. Say for how long and what should wake it. |
| **close** | Not a defect: third-party noise, already fixed, unreachable frame, or the user cancelled. Say which. |

**Stop and wait for confirmation.** This is the one decision the track exists to support;
do not pre-empt it. Record it: `run.sh gate verdict <fix|file|snooze|close> "<why>"`.

On `file`, `snooze` or `close`: carry it out via the Sentry and Linear MCPs, leaving a
note on the Sentry issue that says what was decided and why, then end the run. Closing an
issue without a recorded reason means the next person re-does this analysis.

## 4. On `fix` only

Continue: `branch` → `implement_logic` → `test_unit` → `self_review` → `ship` → `learn`.

The regression test asserts the **error condition**, not the happy path — reproduce the
input shape from the breadcrumbs and prove it no longer throws. Reference the Sentry
issue id in the commit so the next occurrence is traceable to this fix.

After shipping, resolve the Sentry issue in the release that carries the fix, so a
recurrence reopens rather than hiding in an already-resolved issue.

## Anti-patterns

- A try/catch that silences the error without establishing what threw.
- Triaging from the title without opening the stack trace.
- Trusting a minified frame's line number without checking the sourcemap.
- Closing a high-volume issue because it looks cosmetic, without checking user count.
- Fixing an error that the current code can no longer reach.


## Capture what it taught

`/tlv:concept`, at most three, before closing the run. A bug that took an afternoon to
find is the single richest source of concepts there is — the mechanism you had to learn
to see it is exactly what will not be in the diff.

```bash
LEARN="$(dirname "${CLAUDE_PLUGIN_ROOT}")/talview-learn/scripts"
"$LEARN"/journal.sh set "<id>" summary "<what changed, two lines>"
```

Then `/tlv:dashboard` — new concepts are due immediately, so the first revision happens
while it is still fresh.

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
