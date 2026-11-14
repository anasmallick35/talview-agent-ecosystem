---
name: start
description: Entry point for any Talview delivery run. Classifies a Linear ticket, Sentry issue or plain request into a track, gathers its real context, and starts the pipeline. Use when given a ticket URL/ID, a Sentry issue, a user story, or "build/fix/investigate X".
argument-hint: "<linear-url | WFT-1234 | sentry issue id | description>"
---

# Start a delivery run

One entry point. Classify, gather context, start the run, hand off to the track.

`$ARGUMENTS` is the input. If it is empty, ask what to work on — do not guess.

## 1. Classify

Read the input and decide the track. State the classification and why, in one line.

| Signal | Track |
| --- | --- |
| Linear issue typed Feature/Story, or a user story with acceptance criteria | `feature` |
| Linear issue typed Bug, or "X is broken / wrong / not working" | `bug` |
| A `sentry.talview.com` URL, a Sentry issue ID, or "this error" | `sentry` |
| Refactor, migration, dependency bump, cleanup, lint debt, dead code | `tech_debt` |
| Genuinely ambiguous | Ask. One question, with your best guess marked. |

A feature ticket that is really three features is still one intake — the split happens
in `plan`, not here.

## 2. Gather real context

Never work from the ticket title alone.

- **Linear** (`mcp__claude_ai_Linear__get_issue`): description, acceptance criteria,
  comments, labels, parent/sub-issues, attachments, linked designs. Comments routinely
  contain the actual requirement; read them.
- **Sentry** (`mcp__sentry__*`): issue, stack trace, breadcrumbs, tags, event count,
  first/last seen, affected releases.
- **Figma**: if any attachment or comment carries a `figma.com` URL, note it for `audit`.
- **Plain text input**: treat the text as the story. Say explicitly that there is no
  tracker item, because nothing will sync back.

Quote the acceptance criteria verbatim into your summary. Paraphrasing them is how
scope drifts.

## 3. Start the run

```bash
# First run in a workspace, or anything behaving oddly — check the environment.
"$(dirname "${CLAUDE_PLUGIN_ROOT}")"/../talview-core/*/scripts/doctor.sh

"${CLAUDE_PLUGIN_ROOT}"/scripts/skill-map.sh check          # confirm the workspace resolves
"${CLAUDE_PLUGIN_ROOT}"/scripts/run.sh start <TICKET> <track>
```

If `doctor.sh` reports blocking gaps, fix them before starting — a run that fails at
`verify_browser` because credentials were never configured has wasted every phase before
it. Optional gaps are fine to proceed with; name which phases will degrade.

If `skill-map.sh check` reports missing skills, say which phases will degrade to their
fallback before going further. Do not start a run in a workspace where the map does not
resolve at all.

Branch naming follows the workspace convention — check `git log --oneline -20` for the
shape actually in use rather than inventing one.

## 4. Hand off

Announce the track, the phase list, and where the human gate sits. Then invoke the
track skill:

| Track | Skill |
| --- | --- |
| `feature` | `/tlv:feature` |
| `bug` | `/tlv:bug` |
| `sentry` | `/tlv:sentry` |
| `tech_debt` | `/tlv:tech-debt` |

## Rules

- One run per branch. `run.sh start` refuses a second; that is deliberate.
- The run state lives outside the target repo (`~/.talview/<repo>/runs/`). Never write
  agent bookkeeping into the product repository.
- `CLAUDE.md` in the target repo outranks anything in this plugin. Where they conflict,
  follow CLAUDE.md and record the conflict in the ADR.
- Rules learned from review on earlier runs are injected by the SessionStart hook, under
  "Rules learned from review". They are not suggestions and they are not stale: each one
  was written because a reviewer caught it. Honour them for the whole run, and if this
  run contradicts one, say so explicitly rather than quietly ignoring it — that
  contradiction is itself a lesson for `/talview-learn:learn`.
- If that hook reports PRs still owing a harvest, say so at intake. An unharvested PR is
  feedback already paid for and not yet collected.
