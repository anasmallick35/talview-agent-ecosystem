---
name: concept
description: Write a concept note from work just done — what came up, what the code does, how it actually works, better alternatives, pitfalls, and a self-test question. Use at the end of a run, when something took real effort to get right, when review taught something, or on request for a named topic.
argument-hint: "[topic]  (omit to pick from the work just done)"
---

# Capture a concept

The point is not a summary of what was written. It is the understanding that made the
code correct, recorded while it is still in front of you — because in three weeks the
diff survives and the reasoning does not.

```bash
LEARN="$(dirname "${CLAUDE_PLUGIN_ROOT}")/talview-learn/scripts"
```

## 1. Choose, at most three

From the run just done, pick what the work actually *used non-trivially*, what review
flagged, or what cost time to get right. Not only React, and not only frontend: a shell
gate, a GraphQL contract, an RxDB migration, an ICU plural rule, a CI failure and a git
workflow are all concepts, and the ones that cost an afternoon are the ones worth having.

Three is a cap, not a target. Routine work that taught nothing produces nothing — say so
rather than padding. A library that fills with filler stops being read, and an unread
library teaches less than no library.

Already there? Bump it; the counter is what reveals your real curriculum.

```bash
"$LEARN"/concept.sh bump <slug> --entry "<journal-id>"
```

## 2. Write it

```bash
"$LEARN"/concept.sh add <slug> --tags "react,hooks" --entry "<journal-id>" \
  --title "<one line a stranger would understand>" <<'EOF'
## Where it came up
<the ticket, and the specific thing that was wrong or unclear>

## What the code does
```tsx
<the smallest snippet that carries the idea — from the real change>
```

## How it actually works
<the mechanism. Not "useEffect runs after render" — why the cleanup runs before the next
effect AND on unmount, and what breaks when it does not.>

## Better alternatives
1. <alternative> — better when <condition>
2. <alternative> — better when <condition>

## Pitfalls
- <the failure mode, and the symptom you would actually observe>

## Revise with
Q: <a question that cannot be answered by recognising the snippet>
Refs: <doc links>
EOF
```

**The mechanism section carries the value.** Anything restating what the code says is
wasted — the code is already in git. Write what you could not have read off the diff.

**The alternatives section is what keeps you current.** Name when each wins, not which is
"best": an alternative with no condition attached is trivia.

**The question must not be answerable by recognising the snippet**, or revision becomes a
memory test for formatting. Ask why it works, when it breaks, what you would use instead.

## 3. Keep it honest about sources

Write what you verified, not what sounds authoritative. If a mechanism is your reading of
observed behaviour rather than documented, say so in the note — a confident wrong
explanation revised five times is worse than no note, because the ladder will keep
reinforcing it.

Use Context7 or the live docs to check anything you are repeating from memory.

## 4. Then look

`/tlv:dashboard` — new concepts are due immediately, so the first revision happens while
the work is still fresh.
