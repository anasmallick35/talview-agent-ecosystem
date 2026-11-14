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

One command, if you have this repo checked out:

```bash
./bootstrap.sh --workspace /path/to/webclients
```

It is idempotent, registers the marketplace, installs or updates all five plugins, enables
the workspace's MCP servers, seeds `.env`, and ends with the environment check. It touches
nothing in the product repo that is not already gitignored.

Pointing Claude at this repository works too — [`SETUP.md`](SETUP.md) is written as
instructions for an agent to follow.

<details>
<summary>Or do it by hand</summary>

The marketplace carries the plugins. It does not carry the product repo, your
credentials, or your toolchain — so by hand it is four steps, not one.

```bash
# 1. toolchain + product repo
git clone git@github.com:talview/webclients.git && cd webclients
nvm use 24 && pnpm install
gh auth login

# 2. per-machine config the product repo cannot ship for you
#    .claude/settings.local.json is gitignored, so a fresh clone enables no MCP
#    servers at all and playwright/storybook/sentry silently never load.
printf '{"enabledMcpjsonServers":["playwright","storybook","sentry"]}\n' \
  > .claude/settings.local.json
cp .env.example .env 2>/dev/null   # then fill in TEST_AUTH_* and SENTRY_ACCESS_TOKEN

# 3. plugins — this repo is public, so no auth is needed here
claude plugin marketplace add anasmallick35/talview-agent-ecosystem
for p in talview-core tlv talview-verify talview-review talview-learn; do
  claude plugin install "$p@talview"
done

# 4. check what is still missing
~/.claude/plugins/cache/talview/talview-core/*/scripts/doctor.sh
```

Plugins install at **user scope**, so they are live in every project on that machine,
not only the product repo. That is safe: every gate is scoped to a tracked run and every
script fails open, so a repo with no pnpm, no eslint or no git sees nothing at all.

</details>

`doctor.sh` checks the toolchain, `gh` auth, the workspace's own `.claude/skills`, every
plugin, which MCP servers are actually enabled, the credentials each phase needs, and the
services it expects — and prints the fix for each gap. It changes nothing, and you can run
it at any time:

```bash
~/.claude/plugins/cache/talview/talview-core/*/scripts/doctor.sh
```

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

### This repository is public

That is what lets `claude plugin marketplace add` work on any machine with no auth, and
it is the right default for something meant to be shared. It also means nothing internal
can live here.

The one place that matters is the lesson ledger. It lives at `~/.talview/lessons/`, which
is outside this repository and never committed — but lessons are written to be shared, and
harvested review comments quote **private product code**. Write each lesson as the rule and its rationale, not the
snippet it came from. If a lesson cannot be stated without the code, it belongs in the
product repo's own docs instead.

Making this repository private is the alternative, and it is a real trade: installs then
need authentication, and sharing it with another team stops being a one-line command.

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
| `/tlv:review-round` | a round of review, handled: harvest, triage, fix, reply, resolve, learn |
| `/talview-learn:learn` | review feedback into enforcement |

`learn` is the one phase that cannot complete inside the run that triggers it: at `ship`
the code PR is minutes old and has no review. So the track harvests the ADR PR (whose
gate waited for review) and **queues** the code PR. The queue is surfaced at SessionStart
and swept weekly — see [Learning from review](#learning-from-review).

## Daily commands

Scripts live inside the installed plugins and work the same from a shell as from a hook.
Set these once per shell, picking the highest installed version:

```bash
P=~/.claude/plugins/cache/talview
CORE=$(ls -d $P/talview-core/*/scripts | sort -V | tail -1)
TLV=$(ls -d $P/tlv/*/scripts | sort -V | tail -1)
LEARN=$(ls -d $P/talview-learn/*/scripts | sort -V | tail -1)
```

Run them from inside the product repo — every one of them reads the current branch.

### Where am I

```bash
$TLV/run.sh show                  # ticket, track, phase, armed, waivers
$TLV/run.sh next                  # the phase that follows this one
$TLV/skill-map.sh check           # do all workspace skills and agents resolve
$TLV/skill-map.sh phase adr       # what a given phase dispatches to
$CORE/doctor.sh                   # environment gaps and their fixes
```

### Your learning dashboard

```bash
/tlv:concept                      # write up to 3 concept notes from the run just done
/tlv:dashboard                    # build and serve it on localhost:4455
$LEARN/concept.sh due             # what revision is owed
$LEARN/journal.sh open-entries    # runs that recorded nothing
```

Three stores, siblings of each other, all on the shared ledger so every devpod sees one
library:

```
<ledger-root>/journal/   what you did    — seeded automatically by run.sh start
<ledger-root>/concepts/  what it taught  — written while the code is still in front of you
<ledger-root>/lessons/   what review taught — the enforced rules
```

Revision is spaced: a concept resurfaces after 1, 3, 7, 21 then 60 days. Marking it
`shaky` resets it to one day — forgetting is information, so it is treated as such rather
than nudged. Review state is written back to the ledger, not the browser, so it follows
you between containers.

The dashboard is a local Node server with no dependencies and no deploy step. It rebuilds
from the ledger on every request, so there is nothing to invalidate.

### Handling review

```bash
/tlv:review-round                 # every PR the run raised, in one pass
$LEARN/thread.sh list 19574 --repo talview/webclients
$LEARN/thread.sh close <thread-id> <<<"Fixed in abc1234: <what changed>."
```

Harvest before fixing — once the fix is pushed, pairing *what was said* with *what was
done* is guesswork, and the pair is the lesson.

### Driving a run

```bash
$TLV/run.sh start WFT-1234 feature       # usually done for you by /tlv:start
$TLV/run.sh phase implement_ui           # gates idle — still building
$TLV/run.sh phase test_unit              # gates ARM here
$TLV/run.sh gate adr approved "<PR url>"
```

### Pacing a stack

```bash
$TLV/run.sh adr pr|thread|skip           # how this run records its decision
$TLV/run.sh stack init 3                 # 3 PRs agreed
$TLV/run.sh stack pushed "<pr url>"      # PR is up -> HOLD
$TLV/run.sh stack next                   # you said go
```

The hold is enforced: `gh pr create`, `gh stack submit`, `git checkout -b` and
`git worktree add` are denied until a person releases it. Pushing fixes to the PR under
review stays allowed — that is the work the hold exists for.

`stack next` also refuses while the round has recorded nothing. Review happened and the
ledger did not move usually means the argument is still only in a chat window. Say
`--nothing-learned` when a round genuinely taught nothing.

`phase` is the control that arms and disarms the gates. Everything from `test_unit`
onward blocks on missing tests, stories, Cypress specs and locale parity.

### Recording evidence

```bash
$CORE/evidence.sh record lint      pass 'pnpm exec turbo run lint --filter=...'
$CORE/evidence.sh record typecheck pass 'pnpm exec turbo run typecheck'
$CORE/evidence.sh record test      pass 'pnpm --filter @modules/recruit run test'
$CORE/evidence.sh show
```

Record `pass` only for a command you ran and watched succeed. The push gate compares each
timestamp against the newest source edit, so a pass recorded ahead of the work expires the
moment a file changes and blocks you anyway.

### When a gate blocks you

```bash
$TLV/run.sh waive stories "layout-only wrappers, no visual states to document"
```

The reason is mandatory — a waiver without one is just a skip, and the command refuses.
Prefer doing the work; waive only what genuinely does not apply.

### Learning from review

```bash
$LEARN/harvest-recent.sh 7                      # sweep PRs merged in the last week
$LEARN/harvest.sh 17403                         # one PR: threads, replies, resolved state
$LEARN/harvest.sh 17403 --exclude-self          # external reviewers only
$LEARN/lesson.sh add <slug> skill-rule <pr-url> # classify by where it can be enforced
$LEARN/lesson.sh applied <slug> "<where>"       # the rule now exists -> becomes active
$LEARN/lesson.sh bump <slug>                    # seen again; 3+ flags for promotion
$LEARN/lesson.sh list | pending | rules
$LEARN/lesson.sh queue list                     # PRs raised by a run, review not harvested
```

Self-authored comments are included by default and labelled, because the workspace's
`code-review` skill posts under your own account — filtering by author would discard most
of the signal on your own PRs. That matters more than it sounds: **your pushback on a
thread is the highest-signal line in the harvest**, because it is the only place the
codebase's real convention gets stated out loud. Threads carry their resolution state, so
"I argued and the thread closed my way" is distinguishable from "I argued and then caved".

#### Making the second moment automatic

Review lands days after the run ends, so harvesting cannot be something you remember.
Two mechanisms cover it, and neither needs a command:

- **SessionStart** names any queued PR still owing a harvest, in every session on the
  machine. You see it exactly when you sit down to act on the comments.
- **A weekly sweep.** Run once, from inside the product repo:

  ```
  /schedule weekly on Monday 09:00 — run /talview-learn:learn over the PRs that
  harvest-recent.sh 7 reports, then show me lesson.sh pending
  ```

  This needs no workflow in webclients: `harvest-recent.sh` reads the same data from a
  local `gh` session, so nothing is added to a repo the whole team shares.

#### How a lesson reaches the next run

The ledger is not a memory the agent reads; it is a router. A lesson only changes
behaviour once it reaches a destination that acts:

```
review comment + your reply
        │
        ▼  lesson.sh add
   ~/.talview/lessons/<slug>.md          the ledger — outside the plugin, so a plugin
        │                                upgrade cannot abandon it
        ▼  lesson.sh applied
   ~/.talview/lessons/active-rules.md    generated, never hand-edited
        │
        ▼  SessionStart hook
   injected into EVERY session on this machine — tracked run or not
```

#### Where the ledger lives, and sharing it across containers

```
1. TLV_LESSONS_DIR                     explicit override, always wins
2. $CLAUDE_CONFIG_DIR/talview/lessons  when that variable is set
3. $HOME/.talview/lessons              a plain workstation
```

Rule 2 is what makes devcontainers work. Each container gets its own `$HOME`, so a
ledger under it is private to one container and erased by a rebuild. `CLAUDE_CONFIG_DIR`
is already pointed at a mounted volume in that setup — webclients' devcontainer sets it
to `/commandhistory/claude-code` — so following it gives every container one shared,
durable ledger with no change to a devcontainer.json the whole team shares.

An existing `$HOME` ledger is copied across on first use, and the original is left intact.

Temp writes carry `$$`, so two containers on one volume cannot hand each other a
half-written file. `active-rules.md` is derived: if two write it at once, the loser is
rebuilt by `lesson.sh rules`.

`eslint-rule` and `claude-md` lessons stop at the ledger on purpose: they change
webclients, which is shared by the whole team, so they leave as a deliberate PR and never
as a side effect of a feature run. `lesson.sh pending` is that list.

Nothing is injected while a lesson is `open`. `applied` is the switch.

## Tests

```bash
./plugins/talview-core/tests/gates.test.sh    # 16 assertions, no model calls, free
./plugins/talview-learn/tests/lessons.test.sh # 19 assertions — the learning loop
$TLV/skill-map.sh check                       # every phase reference resolves
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
