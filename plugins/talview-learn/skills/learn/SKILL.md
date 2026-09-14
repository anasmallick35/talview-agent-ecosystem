---
name: learn
description: Turn PR review feedback into enforcement. Harvests human comments from a merged or reviewed PR, works out where each lesson can actually be enforced, applies the ones that belong in this plugin, and queues the ones that need a change to the product repo. Use at the end of a run, or on any PR that received substantive review.
---

# Learn

A note nobody reads is not learning. Every lesson here has to end up somewhere that
**acts** — a lint rule, a hook, a rule file a skill loads, or a hard rule in CLAUDE.md.
A lesson with no destination is a lesson that will be re-learned.

## 1. Harvest

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/harvest.sh <pr-number>
```

Bot comments and your own are filtered out; what remains is what a human noticed.

Harvest both PRs from a run: the ADR PR (where design feedback lands) and the code PRs
(where implementation feedback lands). They teach different things — ADR comments tell
you the audit missed something, code comments tell you the implementation did.

## 2. Pair comment with response

For each comment, find what actually changed in reply:

```bash
gh pr diff <pr> --name-only
git log --oneline <base>..<head>
```

The pair — *what was said* and *what was done* — is the lesson. A comment you argued
against and won is also a lesson: it means the reviewer's expectation and the codebase
disagree, which usually means something is undocumented.

Discard: typo fixes, personal style with no rule behind it, and anything already
enforced by tooling that simply was not run.

## 3. Classify by where it can be enforced

This is the step that makes the loop real. Ask: **what is the cheapest thing that would
have caught this automatically?**

| If the lesson is… | Destination | Where it lands |
| --- | --- | --- |
| Mechanically detectable from the AST — "never import X here", "this prop must be set" | `eslint-rule` | `dx/eslint-plugin` in **webclients** → proposed, not applied |
| Detectable the moment a file is written, but not a lint rule — "a new page needs a route permission entry" | `hook` | `talview-core/hooks` → applied here |
| Requires judgment — "prefer composition over a boolean prop here" | `skill-rule` | the relevant skill's `references/` → applied here |
| A recurring principle, seen three or more times | `claude-md` | `CLAUDE.md` in **webclients** → proposed, not applied |

Prefer the cheapest destination that works. A lint rule beats a skill rule, because a
lint rule fires every time and a skill rule fires when a skill is loaded.

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/lesson.sh add <slug> <destination> <pr-url> <<'EOF'
## What was said
> <the comment, verbatim>

## What changed in response
<the fix>

## Why it happened
<the actual cause — a missing rule, an ambiguous rule, a rule that exists but never fires>

## Proposed enforcement
<the rule, hook or text — concrete enough to implement without re-deriving it>
EOF
```

Already recorded? `lesson.sh bump <slug>` instead. At three sightings it becomes a
candidate for promotion to a CLAUDE.md hard rule — repetition is the evidence that the
softer destination is not working.

## 4. Apply what you can

`skill-rule` and `hook` lessons land in this plugin: write the rule file or the hook,
here, now. Then mark it `status: applied`.

`eslint-rule` and `claude-md` lessons **must not be applied**. They change the product
repo, which is shared by the whole frontend team and is not ours to edit as a side effect
of a feature run. Leave them queued:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/lesson.sh pending
```

Surface that list to the human. Raising it is a deliberate, separate PR against
webclients with the rule, its tests (`dx/eslint-plugin` has a test harness — see the
workspace `eslint-plugin-author` skill) and a measured blast radius. That is a decision
for the people who own that config, not a by-product of this run.

## 5. Prove the lesson took

Adding a rule is not evidence it changed behaviour. Add an eval case:

```bash
claude plugin eval ./plugins/<plugin>
```

Each case is a realistic prompt plus a grader, run with and without the plugin, so you
can see what the lesson actually contributes. A lesson that does not move its eval case
was filed in the wrong destination — reclassify it rather than writing it more firmly.

## Anti-patterns

- A growing `notes.md` with no destinations. That is a diary.
- Filing everything as `skill-rule` because it is the easiest to write.
- Editing CLAUDE.md or the workspace ESLint config directly.
- Recording the comment without recording what changed — the pair is the lesson.
- Claiming a lesson is applied without an eval case that moves.
