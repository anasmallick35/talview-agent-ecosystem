# Tooling notes for the audit phase

Verified against `talview/webclients` on 2026-09-14. Re-verify before trusting.

## jscpd — duplication

Works. Handles bracketed route directories correctly.

```bash
npx -y jscpd@latest --min-tokens 50 --min-lines 8 \
  --reporters json --output /tmp/jscpd-out \
  --format "typescript,tsx" --silent <path>

jq '.statistics.total.percentage' /tmp/jscpd-out/jscpd-report.json
jq -r '.duplicates[] | "\(.firstFile.name):\(.firstFile.start) <-> \(.secondFile.name):\(.secondFile.start) (\(.lines)L)"' \
  /tmp/jscpd-out/jscpd-report.json
```

Baseline on `modules/recruit/features/dashboard`: 158 clones, 3.66% of 59,820 lines.
Treat a **rise above the baseline caused by your own change** as the signal. The absolute
number is pre-existing and is not yours to fix.

Read duplicate `messages.ts` blocks as a reuse signal — the same strings defined twice
usually means the same component was built twice.

## knip — dead code

Already a workspace dependency. Run `pnpm exec knip --reporter json`. Useful paired with
jscpd: a block flagged as duplicated **and** an export flagged as unused is a utility
that was bypassed rather than reused.

## ast-grep — deferred, do not use

Two blocking problems found in evaluation:

1. **Silent failure on bracketed paths.** Any path argument containing `[` or `]` returns
   zero matches and exit 0 — no warning. This repo's route directories are
   `workflow[workflowId]overview`, `fullview[evaluationId]` and so on, so whole route
   trees would vanish from a scan with no indication. A tool that silently under-reports
   is worse than no tool.
   (Recursion *into* bracketed directories from a bracket-free argument is fine — the
   problem is only the argument itself.)

2. **Patterns are brittle against this codebase's style.** `export const $N = ($$$) => { $$$ }`
   matches 0 files in `.tsx`, because CLAUDE.md mandates explicit return types and every
   component is written `({ ... }: Props): React.ReactElement => { ... }`. Only fully
   typed patterns match, which defeats the purpose of structural search.

Use `rg` plus the `Explore` agent for the reuse scan instead. Revisit ast-grep if the
path handling is fixed upstream.

## Path handling, generally

Prefer bracket-free directory arguments (`modules/recruit`, not
`modules/recruit/.../workflow[workflowId]overview`) and let tools recurse. When a tool
must receive a bracketed path, quote it and verify the tool returns a non-empty result
for a pattern you know is present — before trusting a zero.
