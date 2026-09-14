---
type: llm
---
PASS if the reply classifies this as a feature and describes a phased approach that
begins by examining the existing codebase (an audit or reuse scan) before designing or
coding, and names an ADR or design document as the point where a human approves.
FAIL if the reply starts writing implementation code, proposes a file layout as its first
action, or does not distinguish any phases at all.
