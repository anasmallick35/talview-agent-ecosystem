# Proposals for `talview/webclients`

Nothing in this directory is applied. These are changes to the **shared org monorepo**
(103 contributors in the last 6 months), so each one is a deliberate PR raised with its
owners — not a side effect of an agent run.

Copy a file to the same path in webclients, open a PR, and cite the rationale below.

## `claude-review.yml` — optional, and probably not first

### What it adds

Claude reviewing pull requests inside GitHub Actions, and responding to `@claude`
mentions on issues and PRs.

### What it does NOT add

It is **not** required for the learning loop. That was the original reason to want it,
and it turned out to be wrong: `talview-learn/scripts/harvest-recent.sh` reads the same
review comments through `gh` from a local session, and a scheduled Claude Code run can
call it. The loop closes with no change to this repository at all.

Run it manually:

```bash
"$(claude plugin path talview-learn 2>/dev/null || echo ~/.claude/plugins/cache/talview/talview-learn/0.1.0)"/scripts/harvest-recent.sh 7
```

Or on a schedule, from a Claude Code session in the webclients checkout:

```
/schedule weekly on Monday 09:00 — run /talview-learn:learn over PRs merged in the last 7 days
```

### So what is it actually for

One thing the local path cannot do: review a PR **before a human opens it**, on every
push, for everyone on the team. That is a team-wide quality decision with a real cost
attached, not a personal workflow improvement.

### Cost and access, stated plainly

- Every PR triggers model calls billed to whichever account the token belongs to.
- It needs `ANTHROPIC_API_KEY` (or OAuth token) as a repository secret. Whoever owns that
  secret pays for every run, including from every other contributor's PRs.
- The workflow needs `pull-requests: write` and `contents: read`.
- On a repo this size, expect it to run many times a day.

### Before proposing it

1. Agree who owns the API cost.
2. Scope `paths:` so it does not run on every change — start with one module.
3. Start with `@claude` mentions only (remove the `pull_request` trigger) so it runs when
   asked rather than always.
4. Confirm with the owners of `.github/workflows/` — there are five existing workflows
   and conventions to match.

Raise it when the team wants it. It is not a prerequisite for anything this ecosystem does.
