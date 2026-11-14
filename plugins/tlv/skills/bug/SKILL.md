---
name: bug
description: The bug delivery track. Reproduce first, find the root cause, get the fix approach approved, then fix with a regression test that fails without the fix. Use after /tlv:start classifies a run as a bug.
---

# Bug track

The gate here is the **fix approach**, not a full ADR. It is smaller than the feature
gate but it is the same gate: the human approves the diagnosis and the plan, then the
work runs.

The discipline that makes this track worth having is refusing to fix anything you cannot
first reproduce and explain. Patch-on-patch debugging is what happens when that step is
skipped.

Advance with `run.sh phase <name>`. Resolve tooling with `skill-map.sh phase <name>`.

## reproduce — before anything else

Load the workspace `systematic-debugging` skill. It exists to stop exactly this failure
mode, so use it rather than reasoning ahead of the evidence.

Establish, concretely:

- The exact steps, data and role that trigger it. Vague steps mean you have not
  reproduced it.
- What actually happens, versus what the ticket says should happen.
- Whether it reproduces on `develop` — if it does not, find the commit that introduced
  it (`git bisect`, or `git log -S` on the relevant symbol).
- Scope: one user, one tenant, one browser, one data shape, or everyone.

**If you cannot reproduce it, stop and say so.** List what you tried and what you need —
a tenant, a record id, a role, a HAR file. Do not guess at a fix for a bug you have not
seen. A fix for an unreproduced bug is an untested change with a ticket number attached.

## root cause

Keep asking why until you reach something that explains *all* the symptoms, not the
first line that looks wrong. Write it as a causal chain:

```
<user action> -> <what the code does> -> <the wrong assumption> -> <observed symptom>
```

State explicitly which layer the cause sits in: component, hook, store/replication,
GraphQL query, permissions, or backend data. If the cause is in the backend, the frontend
fix is a mitigation — say that plainly and file the real fix separately, rather than
letting a workaround close the ticket.

Check whether the same cause exists elsewhere. One root cause with four call sites is
four bugs; fixing one and closing the ticket leaves three.

## approach — **the gate**

Write a fix-approach note into `docs/plans/` (`YYYY-MM-DD-<slug>.md`), unless the fix is
architectural — then it is a real ADR in `docs/adr/` and you follow the feature track's
ADR phase instead.

The note carries: the reproduction, the causal chain, the other call sites found, the
proposed fix, the alternatives rejected and why, and the blast radius — what else touches
this code and could break.

Open a docs-only PR, say you are waiting on review, and **stop**. On resumption read
`gh pr view <N> --comments` and the inline threads, revise, reply to each thread, and
iterate until approved. Then `run.sh gate approach approved "<PR url>"`.

## regression test — before the fix

Write the test that fails **because of the bug**, and watch it fail. A regression test
written after the fix proves only that the code does what it now does.

Put it where the cause is, not where the symptom appeared: a store-layer cause gets a
store-layer test.

## fix

Smallest change that addresses the root cause. Fix every call site the root-cause
analysis found. Resist the tidy-up — an unrelated refactor riding along makes the fix
unreviewable and the revert dangerous.

Then watch the regression test pass, and watch the rest of the suite still pass.

## verify → self_review → ship → learn

`verify_browser` reproduces the original steps and shows the bug is gone — the same
steps, not an approximation of them. Then `code-review` (Trigger B), evidence recorded
via `evidence.sh`, `gh stack submit`, and `/talview-learn:learn`.

The code PR has no review yet. Queue it so the feedback is not lost when it lands —
`"$(dirname "${CLAUDE_PLUGIN_ROOT}")/talview-learn/scripts/lesson.sh" queue add "<pr url>"` —
and harvest the ADR or fix-approach PR now, where comments already exist.

Gates arm from `test_unit`. A bug fix with no test will not pass the Stop gate, which is
the intended outcome.

## Anti-patterns

- Fixing the symptom at the render layer when the cause is in the data layer.
- "Cannot reproduce, but this looks wrong, so I changed it."
- A regression test that passes before the fix.
- Adding a null check where the real question is why the value is null.
- Closing the ticket when the other three call sites still carry the same defect.


## The decision record is a question, not a default

Before writing anything down, ask how this run should record its approach — a docs-only
PR, a note in this thread, or nothing at all because the fix is obvious and the pattern
already exists. Recommend one; record the answer with `run.sh adr pr|thread|skip`. The
approval gate still happens either way; what changes is whether it costs a review round.

## One PR at a time

If this becomes a stack, `run.sh stack init <count>` after the split is agreed, then
`run.sh stack pushed "<url>"` after each push. The hold that follows is enforced, not
advisory: the next PR cannot be started until a person runs `run.sh stack next`. While it
is on, answer threads and push fixes to the same branch — and capture any pushback that
happened in the session with `lesson.sh capture <slug> <adopted|rejected> "<one line>"`,
because nothing else will remember it.
