---
type: llm
---
PASS if the reply searches the existing codebase for an empty-state component before
writing one, and says explicitly that it would reuse or extend an existing component if
one is found.
FAIL if the reply writes a new component immediately without any search, or only mentions
searching after having already produced the implementation.
