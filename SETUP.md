# SETUP — instructions for an agent

If you were pointed at this repository and asked to set it up, follow this file top to
bottom. It is written for you, not for a person reading a tutorial.

This installs a Claude Code plugin ecosystem that carries tickets from intake to an open
pull request. It installs **nothing into the product repository** — that repo is shared by
a whole team and is never modified by setup.

## What you are installing

Five plugins from the `talview` marketplace: `talview-core` (the gates), `tlv` (the
delivery tracks), `talview-verify`, `talview-review`, `talview-learn`.

## Step 1 — Establish the product repo

The tracks dispatch into the product repository's own `.claude/skills/` and `.claude/agents/`.
Without that checkout the skill map resolves nothing and every phase degrades.

Ask the user where their product repo checkout is, unless you are already inside it.
Confirm with `git rev-parse --show-toplevel` and check `.claude/skills/` exists.

Do not clone it for them without asking — it is private, large, and they may already have it.

## Step 2 — Run bootstrap

```bash
./bootstrap.sh --workspace <absolute path to the product repo>
```

It is idempotent and safe to re-run. It registers the marketplace, installs or updates all
five plugins, creates or merges `.claude/settings.local.json` so the workspace's MCP
servers are actually enabled, seeds `.env` from `.env.example` if absent, and finishes by
running the environment check.

If `bootstrap.sh` is not present because you fetched only the README, run the same steps
by hand — the README's setup section lists them.

## Step 3 — Read the environment report

`doctor.sh` runs at the end of bootstrap and separates blocking gaps from optional ones.

**Report every gap to the user with its fix.** Do not paper over one, and do not attempt
to resolve these yourself:

- **Credentials** (`TEST_AUTH_*`, `SENTRY_ACCESS_TOKEN`) — these are secrets. Tell the
  user which are missing and what each unlocks. Never invent values, and never read them
  out of another machine's files.
- **Node version** — if a compatible version is installed but not active, say the exact
  `nvm use` command. Do not change their shell default.
- **Storybook not running** — say the command; do not start a long-running server unasked.
- **Linear and Figma** — these are claude.ai connectors, authorised per account in Claude
  settings. Nothing on this machine enables them.

## Step 4 — Confirm it resolves

```bash
~/.claude/plugins/cache/talview/tlv/*/scripts/skill-map.sh check
```

Expect every workspace skill and agent reference to resolve. If any do not, name them and
say which phases will fall back — a phase that silently does nothing is the failure this
whole system exists to prevent.

## Step 5 — Hand over

Tell the user:

- The one command they need: `/tlv:start <TICKET>`
- That there is exactly one human gate — the ADR (or fix approach), opened as a
  docs-only pull request they review on GitHub. Everything after their approval runs to
  an open PR.
- Any optional gaps from step 3 and which phases those affect.

Do not start a delivery run as part of setup.

## Things to get right

- **Never modify the product repository during setup.** No config changes, no lint-rule
  changes, no dependency changes. The only files bootstrap touches there are
  `.claude/settings.local.json` and `.env`, both gitignored and both per-machine.
- **Plugins install at user scope** and are therefore active in every project on the
  machine. This is safe: every gate is scoped to a tracked run and every script fails
  open, so a repo with no git, no pnpm or no eslint sees nothing at all. Say so if the
  user asks.
- **This repository is public.** Do not commit anything into it that quotes private
  product code — that includes harvested review comments under
  `plugins/talview-learn/lessons/`, which must carry the rule and its rationale rather
  than the snippet.
