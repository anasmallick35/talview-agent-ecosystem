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
| `/tlv:feature` | the feature track |
| `/talview-verify:verify-browser` | drive the real UI, capture evidence |
| `/talview-learn:learn` | review feedback into enforcement |

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
