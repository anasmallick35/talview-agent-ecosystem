---
name: tech-debt
description: The tech-debt track. Map the blast radius, get the approach approved, then make a mechanical change and prove behaviour did not change. Use after /tlv:start classifies a run as a refactor, migration, dependency bump or cleanup.
---

# Tech-debt track

The defining constraint: **behaviour must not change.** That inverts the usual burden of
proof. On a feature you demonstrate that something new works; here you demonstrate that
nothing else broke, which is harder and much easier to fake.

A tech-debt change that alters behaviour is a feature with no ticket, no design and no
review of its intent. Split it.

## 1. Scope and blast radius

Establish exactly what is in scope and how far it reaches:

```bash
rg -l '<symbol>' --type ts --type tsx          # every call site
pnpm exec knip --reporter json                  # dead code that can be deleted instead
npx -y jscpd@latest --min-tokens 50 --reporters json --output /tmp/jscpd-out \
  --format "typescript,tsx" --silent <path>     # duplication the change could collapse
```

Use bracket-free directory arguments — see `audit/references/tooling-notes.md`.

Sometimes the cheapest refactor is a deletion. Check `knip` before restructuring code
that nothing imports.

Record: every call site, which modules are affected, what test coverage exists **today**
over the code being changed, and where coverage is thin. Thin coverage over the blast
radius is the single biggest risk on this track, and it is a finding, not a footnote.

## 2. brainstorm

Load `brainstorming`. Refactors have more viable shapes than features do, and the
difference between them is usually reviewability rather than elegance. Weigh: can this
land in one PR or must it stack; can it be incremental behind a flag; what is the revert
story if it goes wrong in production.

Prefer the approach that can be reverted in one commit.

## 3. approach — **the gate**

An ADR in `docs/adr/` if this changes architecture, a plan in `docs/plans/` if it is
mechanical. Carry: the blast radius, the coverage gap, the chosen sequencing, the revert
story, and explicitly **what behaviour must remain identical**.

Open the docs-only PR, stop, wait for review. Revise against comments, reply to each
thread, iterate to approval. Then `run.sh gate approach approved "<PR url>"`.

## 4. Cover before you change

Where the blast radius has thin coverage, **add tests to the existing code first** and
watch them pass. Those tests are the instrument that detects behaviour change; written
after the refactor, they only describe the new behaviour.

Commit them separately. That commit is independently valuable and independently
revertable.

## 5. Change, mechanically

One kind of change per commit. A rename commit contains renames and nothing else. Mixing
a rename with a signature change makes the diff unreviewable and hides the one line that
actually broke something.

Per stacked PR: keep it independently shippable and independently revertable.

## 6. Prove nothing changed

This is the verification phase, and it is different from every other track:

- Full test suite green, with the **same** pass count as before. A test that disappeared
  is a test that was deleted.
- Type check clean.
- `verify_browser` on the affected flows — the UI behaves identically, network requests
  are the same shape and count. A refactor that changes the request pattern changed
  behaviour.
- Bundle size not materially worse, if you touched imports or code splitting.

Record each via `evidence.sh`. "Looks fine" is not a result on this track.

If you find a genuine bug while refactoring: do not fix it here. File it, note it in the
PR, leave the behaviour as it is. A behaviour change hidden in a refactor is the thing
reviewers cannot see.

## 7. ship → learn

`gh stack submit`, then `/talview-learn:learn`.

The code PR has no review yet. Queue it so the feedback is not lost when it lands —
`"$(dirname "${CLAUDE_PLUGIN_ROOT}")/talview-learn/scripts/lesson.sh" queue add "<pr url>"` —
and harvest the ADR or fix-approach PR now, where comments already exist.

## Anti-patterns

- "Improving" behaviour while refactoring.
- Deleting a test because it broke, rather than because it was wrong.
- One giant PR because the change is "mechanical".
- Refactoring code with no coverage and no new coverage added first.
- Bumping a dependency without reading its changelog for behaviour changes.


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
