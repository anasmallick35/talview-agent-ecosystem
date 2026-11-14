---
name: learn
description: Turn PR review feedback into enforcement. Harvests the threaded comments on a PR — including your own pushback and whether the thread was resolved — works out where each lesson can actually be enforced, applies the ones that belong in this plugin, and queues the ones that need a change to the product repo. Use when review lands on a PR, when you are about to act on review comments, and on the weekly sweep.
---

# Learn

A note nobody reads is not learning. Every lesson here has to end up somewhere that
**acts** — a lint rule, a hook, a rule file injected at session start, or a hard rule in
CLAUDE.md. A lesson with no destination is a lesson that will be re-learned.

## When this runs

Review feedback does not exist when a run ends. The PR is minutes old at `ship`; the
comments arrive days later. So this skill has **two moments**, and only the first one
belongs inside a delivery run.

| Moment | What exists | What to do |
| --- | --- | --- |
| **During the run, whenever the human pushes back in chat** | Nothing yet — it is in the conversation only | `lesson.sh capture <slug> <adopted\|rejected> "<one line>"`, immediately |
| End of a run (`ship`) | The ADR PR's threads, if there was one | Harvest it. Queue each code PR: `lesson.sh queue add <url>` |
| **Review lands on the PRs** | Comments, your replies, resolution state | Run this skill once over the whole queue. The moment that matters |

The second moment reaches you two ways, neither needing you to remember a command: the
SessionStart hook names any PR still owing a harvest, and the weekly sweep
(`harvest-recent.sh 7`) catches whatever was never opened.

**If you are about to act on review comments, harvest first.** Once you have pushed the
fix, the pairing of *what was said* and *what you did* is far harder to reconstruct, and
the pairing is the lesson.

## 1. Harvest — every PR in the run, in one pass

You do not harvest per PR. One invocation covers the whole stack: read the queue, harvest
each PR that has comments, and add the session drafts.

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/lesson.sh queue list     # PRs this run raised
"${CLAUDE_PLUGIN_ROOT}"/scripts/lesson.sh drafts         # pushback captured in session
```

Then one harvest per queued PR:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/harvest.sh <pr-number>
```

So for a three-PR stack that all came back with comments, this skill runs **once** and
reads all three, plus anything captured in the chat. Run it again only when a new round
of review lands.

### Two sources, and only one of them is on GitHub

| Source | Where it comes from | Survives the session? |
| --- | --- | --- |
| PR threads | `harvest.sh` — comments, replies, resolution state | Yes, GitHub keeps it |
| **In-session pushback** | `lesson.sh capture`, at the moment it happened | **Only if it was captured** |

The second is the larger source and the one that leaks. A correction in chat costs the
human one sentence, so they give far more of those than they ever write on a PR — and
none of it is anywhere when the session closes. If a run ends with an empty `drafts` list
after an argument happened, the capture step was skipped, not unnecessary.

Output is **threaded**, each thread carrying its diff hunk, every reply in order, and
whether it ended `RESOLVED` or `UNRESOLVED`. Bots are dropped; your own comments are kept
and labelled `self`, because the workspace `code-review` skill posts under your account.

Harvest both PRs from a run. ADR comments tell you the audit missed something; code
comments tell you the implementation did. They teach different things.

## 2. Classify the session drafts first

`lesson.sh drafts` lists captures with `status: draft` and no destination. Each already
records its `outcome`, which decides how it reads:

- **`adopted`** — the human's position held. That position is the convention. Write it as
  the rule.
- **`rejected`** — their position did not survive contact with the code. The lesson is
  *why*, written so the same argument is not re-run next month. This is not a lesson
  about the human being wrong; it is a lesson about what the code actually requires.

Give each a destination and promote it out of `draft` with `lesson.sh add` (or edit the
file in place and set `status: open`). A draft left unclassified is injected nowhere.

## 3. Pair the comment with what happened

For each thread, three outcomes, three different lessons:

| Thread | Means | The lesson |
| --- | --- | --- |
| Comment → you changed the code | The rule exists and you missed it | Why did nothing catch it before review? |
| Comment → **you pushed back and the thread resolved your way** | The reviewer's expectation and the codebase disagree | Something is undocumented. Write down what you argued — that argument is the rule |
| Comment → nothing changed, still unresolved | Unactioned | Not a lesson yet. Go answer it |

The second row is the one most setups throw away. Your pushback is the most informative
signal in the whole harvest: it is the only place where the codebase's real convention
gets stated out loud, because nothing else forced anyone to state it.

Confirm what actually changed:

```bash
gh pr diff <pr> --name-only
git log --oneline <base>..<head>
```

Discard: typo fixes, personal style with no rule behind it, and anything already enforced
by tooling that simply was not run.

## 4. Classify by where it can be enforced

Ask: **what is the cheapest thing that would have caught this automatically?**

| If the lesson is… | Destination | Where it lands |
| --- | --- | --- |
| Mechanically detectable from the AST — "never import X here", "this prop must be set" | `eslint-rule` | `dx/eslint-plugin` in **webclients** → proposed, not applied |
| Detectable the moment a file is written, but not a lint rule | `hook` | `talview-core/hooks` → applied here |
| Requires judgment — "prefer composition over a boolean prop here" | `skill-rule` | the ledger's `active-rules.md`, injected at every SessionStart → applied here |
| A recurring principle, seen three or more times | `claude-md` | `CLAUDE.md` in **webclients** → proposed, not applied |

Prefer the cheapest destination that works. A lint rule beats an injected rule, because a
lint rule fires on the code and an injected rule only fires on attention.

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/lesson.sh add <slug> <destination> <pr-url> <<'EOF'
## What was said
> <the comment, verbatim>

## What changed in response
<the fix — or "nothing: I pushed back and the thread resolved unchanged">

## Why it happened
<the actual cause — a missing rule, an ambiguous rule, a rule that exists but never fires>

## Proposed enforcement
<the rule, in one or two lines. This text is what gets injected into future sessions,
so write it as an instruction, not as a story.>
EOF
```

Already recorded? `lesson.sh bump <slug>` instead. At three sightings it becomes a
candidate for promotion to a CLAUDE.md hard rule — repetition is the evidence that the
softer destination is not working.

## 5. Apply what you can, then say so

`skill-rule` and `hook` lessons land here: write the rule file or the hook, now. Then:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/lesson.sh applied <slug> "<where the enforcement lives>"
```

That is not bookkeeping. `applied` is what moves the lesson into `active-rules.md`, and
`active-rules.md` is what the SessionStart hook injects into **every** future session on
this machine. A lesson left `open` changes nothing, however well written.

`eslint-rule` and `claude-md` lessons **must not be applied**. They change the product
repo, which is shared by the whole frontend team and is not ours to edit as a side effect
of a feature run. Leave them queued, and surface the list:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/lesson.sh pending
```

Raising one is a deliberate, separate PR against webclients with the rule, its tests
(`dx/eslint-plugin` has a harness — see the workspace `eslint-plugin-author` skill) and a
measured blast radius. That is a decision for the people who own that config.

Finally, close the queue entry:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/lesson.sh queue done <pr-url>
```

## 6. Prove the lesson took

Adding a rule is not evidence it changed behaviour. Add an eval case:

```bash
claude plugin eval ./plugins/<plugin>
```

Each case is a realistic prompt plus a grader, run with and without the plugin, so you can
see what the lesson actually contributes. A lesson that does not move its eval case was
filed in the wrong destination — reclassify it rather than writing it more firmly.

## Where the ledger lives

`~/.talview/lessons/` — outside the plugin, deliberately. The plugin installs into a
version-pinned cache directory, so a ledger stored inside it is abandoned by the next
release of this plugin. Override with `TLV_LESSONS_DIR`.

This repository is public. Write each lesson as the rule and its rationale, never the
private snippet it came from. If a lesson cannot be stated without the code, it belongs in
the product repo's own docs.

## Anti-patterns

- A growing `notes.md` with no destinations. That is a diary.
- Filing everything as `skill-rule` because it is the easiest to write.
- Recording the comment without recording what happened — the pair is the lesson.
- Leaving a lesson `open` after writing its rule. Nothing is injected until `applied`.
- Harvesting after you have already fixed the comments.
- Editing CLAUDE.md or the workspace ESLint config directly.
