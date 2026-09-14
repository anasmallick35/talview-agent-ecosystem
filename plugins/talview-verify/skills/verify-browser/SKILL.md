---
name: verify-browser
description: Drive the real running app and produce evidence that a change works — network requests and their payloads, console errors, keyboard and a11y behaviour, screenshots. Use after implementation, before self-review, whenever a change touches UI or backend integration.
---

# Browser verification

The output of this phase is **evidence**, not reassurance. "I verified it works" is not a
result; a captured request with a real payload is.

Two tools, different jobs. Playwright drives; Chrome DevTools observes.

| Need | Tool |
| --- | --- |
| Click, type, navigate, assert structure | `mcp__playwright__*` — accessibility tree, not pixels |
| Did the request fire, what came back, any console error, how slow | `mcp__chrome-devtools__*` |

## 1. Get in

Use the workspace `playwright-login` skill. It mints a `custom_token` from
`@packages/test-utils` using env-managed credentials and hands it to v8 via
`?custom_token=` — headless, no OTP. Do not attempt an interactive login.

Serve the app if it is not already running: `pnpm --filter @v8/app run serve`.

## 2. Walk the change

Drive the actual user path the ticket describes, end to end. Not the happy path only —
the states you were told to build:

- golden path
- every branching flow the acceptance criteria name
- form validation, if there is a form
- error and failure states (force them: offline, 500, empty response)
- loading and empty states
- permission-gated variants, if the feature is gated
- navigation and URL state, including refresh and back

Take a screenshot at each meaningful state.

## 3. Prove the integration

This is the part Cypress does not answer and the part that matters most when the backend
was mocked during development.

```
mcp__chrome-devtools__* → list network requests for the interaction
```

Check, and record:

- The expected request **actually fired** — not served from a stale cache.
- Its status is 2xx.
- The response carries **real data**, not the MSW fixture. If the shape matches the mock
  exactly, suspect the mock is still wired and say so.
- No request fired that should not have — an N+1 in the network panel is a finding.
- The console is clean. Any `error` is a defect until proven otherwise; capture it.

If this run is still on the MSW contract path because the backend does not exist yet,
state that plainly. Verified-against-a-mock is a real result, but it is a different
result from verified-against-the-backend, and conflating them is how integration bugs
reach production.

## 4. Keyboard and a11y smoke

- Tab through the feature. Every interactive element reachable, focus visible, order
  sensible.
- Enter activates, Escape dismisses.
- Interactive elements have accessible names.

Full audit is the workspace `web-interface-audit` skill and the `accessibility-expert`
agent. This is the smoke check that catches the obvious.

## 5. Record

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/verify-evidence.sh init
"${CLAUDE_PLUGIN_ROOT}"/scripts/verify-evidence.sh note  <<'EOF'
...findings...
EOF
```

Evidence lands in `~/.talview/<repo>/runs/<branch>.verify/` — outside the product repo.

Then record the outcome so the push gate can see it:

```bash
EV="$(dirname "$(dirname "${CLAUDE_PLUGIN_ROOT}")")/talview-core/0.1.0/scripts/evidence.sh"
"$EV" record browser pass '<what was driven>' '<backend: real | msw>'
```

Record `pass` only if you drove it and watched it work. A `pass` recorded from reading
the code is a lie the gate will happily believe, and it is the one failure this whole
system cannot catch.

## Reporting

Say what you drove, what you observed, and what you could not check. An honest
"could not force the 500 path" is worth more than silence, because silence reads as
"checked and fine".
