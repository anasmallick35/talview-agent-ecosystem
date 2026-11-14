---
name: dashboard
description: Open the personal learning dashboard — what you did day by day, the concepts the work taught, what revision is due, and the rules review has produced. Builds from the local ledger and serves it on localhost. Use for "open my dashboard", "what did I do this week", "what should I revise", or at the end of a run.
argument-hint: "[port]  (default 4455)"
---

# Learning dashboard

Local only. Nothing is deployed, nothing is uploaded; the page is rebuilt from the ledger
on every request, so there is no stale build to refresh.

```bash
LEARN="$(dirname "${CLAUDE_PLUGIN_ROOT}")/talview-learn/scripts"
"$LEARN"/dashboard.sh serve "${ARGUMENTS:-4455}"
```

Run it in the background and give the human the URL. In a devpod the port is forwarded on
first access, so `localhost` works the same there as on a laptop.

## Before serving, close the gaps

A dashboard that shows an empty week is worse than none — it reads as "you learned
nothing" when it means "nothing was captured". So check first:

```bash
"$LEARN"/journal.sh open-entries     # runs with no concept recorded
"$LEARN"/concept.sh due              # what revision is owed
"$LEARN"/lesson.sh drafts            # pushback captured but never classified
```

If `open-entries` lists anything from work done in this session, write those concepts now
— see `/tlv:concept`. Reconstructing them next week from a diff is guesswork; the reason
a thing was hard is only legible while it is still in front of you.

## What each view is for

| View | Question it answers |
| --- | --- |
| **Revision** | What am I about to forget? Self-test first, reveal second, honest answer third |
| **Timeline** | What did I actually do this day / week / month? |
| **Concepts** | The library, ranked by how often each came up — that ranking *is* the curriculum |
| **Lessons** | What review taught, and which rules are enforced now |
| **Stats** | Runs by track and month, concepts by tag |

## On the revision tab

Marking `shaky` is not failure, it is the signal the schedule runs on: it resets the
interval to one day so the concept comes back while it is still recoverable. A library
where everything is marked `known` has stopped measuring anything.

Review state is written back into the ledger, so it follows you to every devpod sharing
the volume rather than dying with the browser tab.

## Reporting

Say the URL, the counts (entries, concepts, due), and anything uncaptured. Do not
summarise the dashboard's contents back at the human — they are about to look at it.
