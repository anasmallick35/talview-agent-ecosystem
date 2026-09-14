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
# once per machine
claude plugin marketplace add anasmallick35/talview-agent-ecosystem

# per workspace
/plugin install talview-core@talview
/plugin install talview-delivery@talview
/plugin install talview-verify@talview
/plugin install talview-review@talview
/plugin install talview-learn@talview
```

Local development against a checkout:

```bash
claude --plugin-dir ./plugins/talview-core
```

## Plugins

| Plugin | What it does |
| --- | --- |
| `talview-core` | The enforcement layer. Edit-time lint feedback, definition-of-done gate, evidence-gated push, session state injection. |
| `talview-delivery` | Intake router plus feature, bug, sentry and tech-debt tracks. Carries a ticket from audit through ADR to an open PR. |
| `talview-verify` | Browser, network and accessibility verification that produces evidence artifacts rather than claims. |
| `talview-review` | React/TypeScript code quality rubric, applied before writing and when reviewing a diff. |
| `talview-learn` | Harvests PR review feedback and routes each lesson to lint, hook, skill or CLAUDE.md. |

## Per-workspace configuration

`talview-core` ships defaults in `plugins/talview-core/config/defaults.json`. A workspace
overrides them with `.tlv/config.json` at its repo root:

```json
{
  "baseBranch": "develop",
  "dod": { "requireStories": false },
  "push": { "requiredEvidence": ["lint", "test"] }
}
```

## Run state

A tracked run lives in `.tlv/runs/<branch-slug>.json` in the target workspace:

```json
{
  "ticket": "WFT-5456",
  "track": "feature",
  "phase": "implement",
  "waivers": {},
  "gateBlocks": 0
}
```

`phase` decides which gates are live. Outside a tracked run the gates stay silent, so
ad-hoc sessions behave exactly as they did before. `.tlv/runs/<branch-slug>.evidence.json`
is the ledger the push gate reads.

Add `.tlv/` to the target repo's `.gitignore`.
