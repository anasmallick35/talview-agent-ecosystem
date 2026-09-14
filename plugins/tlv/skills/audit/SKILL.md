---
name: audit
description: The audit phase of a delivery run. Scans the codebase for what already exists before anything is designed — reuse candidates, the patterns actually in use, design source, backend availability — and produces the evidence the ADR is built from. Use at the start of any feature, tech-debt or non-trivial bug run.
---

# Audit

The purpose is to know what already exists before deciding what to build. An audit that
only re-states the ticket is worthless; this one has to come back with findings that
change the design.

Run the four scans **in parallel** as subagents. Each returns findings only — no files
written, no decisions made. You synthesise.

## Scan 1 — Reuse

The question: *which requirements are already satisfied by code in this repo?*

Use `rg` for the search and the `Explore` agent for the semantic sweep — Explore is
better than any pattern language at "is there already something that does this", because
the thing you would have written is rarely named what you would have named it. Search by
capability and by prop shape, not by the name you had in mind.

Then check what the repo already duplicates:

```bash
npx -y jscpd@latest --min-tokens 50 --min-lines 8 --reporters json \
  --output /tmp/jscpd-out --format "typescript,tsx" --silent <path>
pnpm exec knip --reporter json            # already a workspace dependency
```

A block jscpd flags as duplicated **and** knip flags as an unused export is a utility
somebody bypassed — the strongest possible reuse signal.

Read `references/tooling-notes.md` before running any of these. It records verified
invocations, the jscpd baseline to compare against, and why `ast-grep` is deliberately
not used here.

Search in this order, and stop at the first tier that satisfies the requirement:

1. `@teserra/*` — atoms, molecules, organisms
2. `@packages/*` — hooks, utils, components, store, types
3. The target module's own `features/*/components/`
4. Other modules — **read-only**. A cross-module import is forbidden by CLAUDE.md; a
   match here means "promote to `packages/`", not "import it".

Return, per requirement: `build-new` | `reuse <path>` | `extend <path>`, with the
evidence. A `build-new` verdict must say what was searched for and why nothing matched —
an unsupported `build-new` is the single most expensive mistake this phase can make.

## Scan 2 — Pattern

The question: *what does this repo actually do today, as opposed to what it says?*

Find the **three most recently merged** comparable features:

```bash
git log --since='4 months ago' --diff-filter=A --name-only --format='%h %ad %s' \
  --date=short -- 'modules/*/features/*' | head -80
```

Recency matters. The oldest example of a pattern is usually the one that was later
regretted. Where the recent code and `CLAUDE.md` disagree, **`CLAUDE.md` wins** and the
disagreement is recorded — that record is a finding, not a footnote.

Return: file layout, data-access approach (store facade vs Apollo, and why), state
placement, test/story/e2e shape, telemetry and i18n conventions, plus every conflict
found between recent practice and the written rules.

## Scan 3 — Design

| Situation | Action |
| --- | --- |
| A `figma.com` URL exists | `mcp__claude_ai_Figma__get_design_context` for structure, variables and tokens; `get_code_connect_map` to resolve Figma components to real Teserra components. Never build from a screenshot when the file is reachable. |
| No Figma, but the pattern exists in the product | Derive the composition from Storybook (`mcp__storybook__*`) and from the comparable features in Scan 2. Name the source. |
| Neither | Compose from Teserra primitives and state plainly that the visual design is inferred. Do not invent a novel layout quietly. |

Every Teserra export is verified through the Storybook MCP before it is used. Only
`Heading`, `Paragraph` and `Label` are safe to assume.

## Scan 4 — Backend

Establish whether the data this feature needs exists:

- Search `*.gql` and the generated types for the operations required.
- Check `packages/store` collections and their replication for the entities involved.
- Check `docs/adr/` for a backend ADR describing a contract that is agreed but unbuilt.

Three outcomes:

1. **Available** — name the operations and types. Proceed normally.
2. **Contracted but unbuilt** — a backend ADR or ticket defines the shape. Take the
   contract, generate MSW handlers and types from it, build the UI against them, and
   record a separate blocked task for real wiring. This is the agreed default.
3. **Undefined** — no contract exists. Write the contract you need into the audit as a
   proposal, build against MSW, and flag it as the highest-risk assumption in the run.
   Do not silently invent a schema and let it look settled.

## Synthesis

Produce one audit document. It is the input to the ADR, and it is what makes the ADR
reviewable rather than plausible.

```markdown
# Audit — <TICKET> <title>

## Acceptance criteria (verbatim)
## Reuse verdicts            <!-- requirement -> build-new | reuse <path> | extend <path> -->
## Pattern to follow         <!-- with the commits it was derived from -->
## Rule conflicts found      <!-- recent practice vs CLAUDE.md, and which wins -->
## Design source             <!-- figma | storybook-derived | inferred -->
## Backend status            <!-- available | contracted | undefined + contract -->
## Gaps and assumptions      <!-- every ambiguity, the assumption taken, and its blast radius -->
## Out of scope              <!-- what this run will NOT do -->
```

**Gaps do not stop the run.** Each gap is written down with the assumption chosen and
why. The human reviews them at the ADR gate, which is the one place they are asked to
decide anything. A gap you failed to write down is a gap that ships.

Sort gaps by how expensive they are to be wrong about, not by how uncertain they are.

## Anti-patterns

- Re-stating the ticket as "findings".
- `build-new` with no record of what was searched.
- Copying the oldest matching pattern because it appeared first in grep.
- Treating a screenshot as the design when the Figma file is reachable.
- Inventing a GraphQL schema and presenting it as though it were agreed.
