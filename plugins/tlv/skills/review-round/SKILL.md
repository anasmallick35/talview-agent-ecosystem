---
name: review-round
description: Handle a round of PR review end to end — harvest every PR the run raised, triage each thread with you, fix the valid ones on their own branches, reply and resolve, and record what was learned. Use when review comments land on one or more PRs from a run, or when asked to "handle the review comments" or "resolve the PR comments".
argument-hint: "[pr-number …]  (default: every PR this run queued)"
---

# Review round

One round of review, handled completely: harvest, triage, fix, reply, resolve, learn.

The order is not arbitrary. **Harvest before touching code.** Once a fix is pushed, the
pairing of *what was said* and *what was done* is hard to reconstruct, and that pair is
the lesson. Fixing first and harvesting after yields comments with no outcomes attached.

## 1. Collect

```bash
LEARN="$(dirname "${CLAUDE_PLUGIN_ROOT}")/talview-learn/scripts"
"$LEARN"/lesson.sh queue list     # every PR this run raised
"$LEARN"/lesson.sh drafts         # pushback captured in this session
```

`$ARGUMENTS` overrides the queue when given. Otherwise harvest each queued PR:

```bash
"$LEARN"/harvest.sh <pr> [--repo <owner/name>]
```

Each thread prints with its id (`thread: PRRT_…`), its replies in order, its resolution
state and the diff hunk. The id is how you answer it later — never match on body text,
which breaks the moment someone edits a comment.

## 2. Triage — with the human, before anything is pushed

Present every open thread as a table: the PR, the file, what was said, and your proposed
disposition. Three dispositions, and only three:

| Disposition | Means |
| --- | --- |
| **fix** | The comment is right. State the change you intend, not just "will fix" |
| **discard** | Style with no rule behind it, or already handled. Say why, briefly |
| **disagree** | You think the comment is wrong. State the reason you will post |

**Stop and let them correct the triage.** This is the one checkpoint in the round, and it
is cheap: a wrong disposition costs a push and a reversal, a wrong triage caught here
costs a sentence. If they overrule you on a thread, that is itself a lesson — capture it
in step 5 with outcome `rejected`.

Never mark a thread `discard` to make the list shorter. A reviewer who sees a thread
closed without an answer learns not to leave comments.

## 3. Fix — each on its own branch

A comment on PR 1 is fixed on **PR 1's branch**. Rolling PR 1's fix into the branch you
happen to be standing on is how a stack stops being independently reviewable, and the
reviewer who asked gets a PR that still shows the problem.

```bash
git checkout <pr-1-branch>     # the stack hold allows this: it is not a NEW branch
# make the change, with the phase skills the work calls for
git commit && git push
```

Run the tests the change touches and record it — the push gate reads the ledger and a
pass that predates the edit does not count:

```bash
"$(dirname "${CLAUDE_PLUGIN_ROOT}")"/talview-core/scripts/evidence.sh record test pass '<cmd>'
```

## 4. Answer every thread

Every thread gets a reply. A silently-closed thread is the failure this step exists to
prevent.

```bash
# fixed it — say what changed, then close
"$LEARN"/thread.sh close <thread-id> <<'EOF'
Fixed in <sha>: <what changed, concretely>.
EOF

# disagreed — say why, and leave it OPEN for them to answer
"$LEARN"/thread.sh reply <thread-id> <<'EOF'
Not changing this, because <reason>. Happy to be overruled.
EOF
```

Resolve what you fixed or declined with a reason. **Never resolve a thread you are
quietly dropping** — resolved reads as "handled", and spending that signal is hard to
undo.

## 5. Record what the round taught

Three sources, all going to the same ledger:

```bash
# a reviewer caught something
"$LEARN"/lesson.sh add <slug> <destination> <pr-url> <<'EOF'
## What was said
> <verbatim>
## What changed in response
<the fix — or "nothing: I disagreed and the thread resolved unchanged">
## Why it happened
<the real cause>
## Proposed enforcement
<the rule, as an instruction>
EOF

# the human overruled your triage in step 2
"$LEARN"/lesson.sh capture <slug> rejected "<what you proposed, and why it did not hold>"

# the human backed your disagreement
"$LEARN"/lesson.sh capture <slug> adopted  "<the convention that got stated out loud>"
```

Then the step that makes any of it matter:

```bash
"$LEARN"/lesson.sh applied <slug> "<where the enforcement now lives>"
```

A lesson left `open` is injected nowhere. `applied` is the switch. Classify every draft
from step 1 too — a capture that is never classified was a note, not a lesson.

Finally close the queue entries you harvested:

```bash
"$LEARN"/lesson.sh queue done <pr-url>
```

## 6. Report

Say, in this order:

1. What was fixed, per PR, with the commit
2. **What you pushed back on and why** — name it, do not bury it
3. What became a rule, and where it now lives
4. What is sitting in `lesson.sh pending`, needing a webclients PR **they** must raise
5. Anything left unresolved and waiting on them

Do not claim the round is done while a thread is unanswered. "All comments addressed" is
checkable, and someone will check it.

## Rules

- Harvest before fixing. Always.
- Every thread gets a reply; resolve only what you answered.
- Fixes land on the branch of the PR that was commented on.
- The triage is a checkpoint, not an announcement — wait for the human.
- This skill does not advance the stack. Releasing the hold is `run.sh stack next`, and
  that is the human's call.
