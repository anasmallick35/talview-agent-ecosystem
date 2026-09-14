---
type: llm
---
PASS if the reply treats triage as the goal and says it will end in a verdict the human
confirms — fix, file, snooze or close — and says it will check the stack frames against
the current code before deciding.
FAIL if the reply assumes the issue must be fixed in code, or proposes a fix without
mentioning verification of the frames or a verdict step.
