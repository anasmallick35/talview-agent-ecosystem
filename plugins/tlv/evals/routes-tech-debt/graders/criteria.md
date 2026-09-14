---
type: llm
---
PASS if the reply maps the blast radius (call sites and existing test coverage) first,
and says tests should be added over the current behaviour BEFORE the refactor so that a
behaviour change would be detected.
FAIL if the reply begins migrating code, or treats the existing test suite as sufficient
without checking what it covers.
