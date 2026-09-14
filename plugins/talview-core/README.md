# talview-core

The layer that cannot be skipped.

## Hooks

| Event | Script | Effect |
| --- | --- | --- |
| `SessionStart` | `session-context.sh` | Injects ticket, track, phase, evidence status and open gaps for the current branch. Silent outside a tracked run. |
| `PostToolUse(Write\|Edit)` | `post-edit-lint.sh` | Runs the repo's own ESLint on the file just written and returns violations in the same turn. Never blocks. |
| `PreToolUse(Bash)` | `pre-push-gate.sh` | Denies `git push` unless the branch can prove it is done. Denies pushes to `develop`/`main`/`master` outright. |
| `Stop` | `dod-gate.sh` | Refuses to end the turn while artifact obligations are unmet. Loop breaker after 4 consecutive blocks. |

## What "done" means

`dod-check.sh` is the single definition, shared by the Stop gate and the push gate:

- Every changed `.tsx` under `v8/` or `modules/` has a unit test — sibling `X.test.tsx`,
  `tests/index.test.tsx`, or `__tests__/`.
- Every changed `.tsx` under `components/`, `atoms/`, `molecules/` or `organisms/` has a
  `.stories.tsx`.
- A newly added `pages/**/index.tsx` requires a Cypress spec in the same change.
- Every locale key **this branch adds** to `en.json` exists in every sibling locale file.
  Pre-existing drift is not attributed to the branch.

Generated, mock, fixture and storybook-helper paths are excluded.

## Why the push gate replaces the confirmation prompt

The standing policy is autonomous delivery to an open PR, so the per-push human
confirmation is replaced by verification. `git push` is denied unless:

1. `dod-check.sh` is clean, **and**
2. `lint`, `typecheck` and `test` each have a recorded pass in the evidence ledger, **and**
3. no recorded pass predates the newest source edit on the branch.

Point 3 is the one that matters. A green test run only proves something about the code
that ran; edit a file afterwards and the proof goes stale and stops counting.

Record evidence only after a command genuinely passes:

```bash
"${CLAUDE_PLUGIN_ROOT}"/scripts/evidence.sh record test pass 'pnpm --filter @modules/recruit run test'
```

`gh stack` pushes are passed through — that tooling owns the sanctioned rebase and
force-push path.

## Failure behaviour

Every script fails open. A missing `jq`, a broken git state or a lint timeout produces
silence, never a blocked session. The gates are strict about code and permissive about
themselves.
