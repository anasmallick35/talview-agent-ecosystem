# Talview Agent Ecosystem

A Claude Code plugin marketplace for Talview frontend work: deterministic guardrails,
ticket-to-PR pipelines, verification, review rules, and a self-improvement loop.

## Why this exists

Writing more instructions does not make an agent follow them. Instructions are
probabilistic; the rules that matter have to be enforced by something that can say no.

This repo is organised around that split:

| Layer | Mechanism | Skippable |
| --- | --- | --- |
| **L0** Deterministic gates | hooks, ESLint, CI | No — a hook exits 2 and the call does not happen |
| **L1** Evidence gates | Stop and pre-push hooks that demand proof of done | No |
| **L2** Procedure | skills | Yes |
| **L3** Judgment | subagents, ADR authoring | Yes |

Most agent setups are all L2. The gap between "the rule is written down" and "the rule
held" is L0 and L1.

## Install

```bash
claude plugin marketplace add anasmallick35/talview-agent-ecosystem

/plugin install talview-core@talview     # gates — install this one everywhere
/plugin install tlv@talview              # the delivery tracks
/plugin install talview-verify@talview
/plugin install talview-review@talview
/plugin install talview-learn@talview
```

## Setting up a new machine

The marketplace carries the plugins. It does not carry the product repo, your
credentials, or your toolchain — so installing is three steps, not one.

```bash
# 1. toolchain + product repo
git clone git@github.com:talview/webclients.git && cd webclients
nvm use 24 && pnpm install
gh auth login

# 2. plugins
claude plugin marketplace add anasmallick35/talview-agent-ecosystem
for p in talview-core tlv talview-verify talview-review talview-learn; do
  claude plugin install "$p@talview"
done

# 3. check what is still missing
~/.claude/plugins/cache/talview/talview-core/*/scripts/doctor.sh
```

`doctor.sh` checks the toolchain, `gh` auth, the workspace's own `.claude/skills`,
every plugin, the credentials each phase needs, and the services it expects — and prints
the fix for each gap. It changes nothing.

### What needs credentials, and where they come from

| Needs | For | Where |
| --- | --- | --- |
| `gh auth login` | ADR PRs, comment harvesting | per machine |
| `TEST_AUTH_USERNAME` / `PASSWORD` / `TENANT_ID` | `verify_browser` sign-in | `.env` in the product repo, or AWS Secrets Manager fallback |
| `SENTRY_ACCESS_TOKEN` | the Sentry track | `.env` in the product repo |
| Storybook on `:4450` | verifying Teserra props instead of guessing | `pnpm --filter @dx/storybook run serve` |
| Linear, Figma | intake, design resolution | claude.ai connectors — OAuth **per account**, authorise once, follows you to any machine |
| Chrome DevTools, Context7 | network evidence, library docs | nothing — `npx`, no credentials |

Browser verification is headless and mints a token from `@packages/test-utils`; there is
no interactive login and no OTP. But it still needs those three `TEST_AUTH_*` values, so
"no username and password" is only true of the *session*, not of the setup.

## Use it

```
/tlv:start WFT-1234                 classify, gather context, start a run
/tlv:start https://linear.app/...   a ticket URL works too
```

`start` routes to a track. The feature track has exactly one human gate: the ADR, opened
as a docs-only pull request you review and approve. Everything after approval runs to an
open PR without stopping.

| Skill | Phase |
| --- | --- |
| `/tlv:start` | classify and route |
| `/tlv:audit` | reuse, pattern, design and backend scans |
| `/tlv:feature` | feature track — gate is the ADR |
| `/tlv:bug` | bug track — gate is the fix approach, reproduce first |
| `/tlv:sentry` | Sentry track — gate is the verdict: fix, file, snooze or close |
| `/tlv:tech-debt` | tech-debt track — gate is the approach, prove nothing changed |
| `/talview-verify:verify-browser` | drive the real UI, capture evidence |
| `/talview-learn:learn` | review feedback into enforcement |

## Tests

```bash
./plugins/talview-core/tests/gates.test.sh    # 16 assertions, no model calls, free
claude plugin validate ./plugins/<name>
claude plugin eval ./plugins/tlv              # skill routing — costs model calls
```

Gate behaviour is covered by shell tests rather than `claude plugin eval`, deliberately:
eval runs start in an empty directory with no git repo, no pnpm and no eslint, where every
gate correctly does nothing. Model-call evals cannot observe behaviour that only exists
inside a real repository.

The `evals/` suite under `plugins/tlv` covers what evals *are* good at — whether a skill
fires on natural phrasing, and whether it stays quiet when it should. It is written to the
documented format but **not yet verified**: `claude plugin eval` is early-access and
refused to run on CLI 2.1.227. Run `claude update` first.

## Proposals

`proposals/webclients/` holds changes to the product repo that are **not applied**. That
repo is shared by the whole frontend team, so each is a deliberate PR raised with its
owners. Nothing this ecosystem does depends on one landing.

Local development against a checkout:

```bash
claude --plugin-dir ./plugins/talview-core
```

## Plugins

| Plugin | What it does |
| --- | --- |
| `talview-core` | The enforcement layer. Edit-time lint feedback, definition-of-done gate, evidence-gated push, session state injection. |
| `tlv` | Intake router plus the delivery tracks. Carries a ticket from audit through ADR to an open PR. |
| `talview-verify` | Browser, network and accessibility verification that produces evidence artifacts rather than claims. |
| `talview-review` | React/TypeScript code quality rubric, applied before writing and when reviewing a diff. |
| `talview-learn` | Harvests PR review feedback and routes each lesson to lint, hook, skill or CLAUDE.md. |

## Per-workspace configuration

`talview-core` ships defaults; a workspace overrides them at
`~/.talview/<repo>/config.json`:

```json
{
  "baseBranch": "develop",
  "dod": { "requireStories": false },
  "push": { "requiredEvidence": ["lint", "test"] }
}
```

## Run state

A tracked run lives **outside** the target repo, in `~/.talview/<repo>/runs/<branch-slug>.json`.
The product repository is a deliverable, not a scratchpad — it never needs a `.gitignore`
entry for our bookkeeping:

```json
{
  "ticket": "WFT-5456",
  "track": "feature",
  "phase": "implement",
  "waivers": {},
  "gateBlocks": 0
}
```

The track sets `armed` when a phase is past building, and that is the only thing the
gates read — `talview-core` does not know the track's phase names. Outside a tracked run
the gates stay silent, so ad-hoc sessions behave exactly as they did before.
`<branch-slug>.evidence.json` alongside it is the ledger the push gate reads.
