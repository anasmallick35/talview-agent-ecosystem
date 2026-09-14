---
type: llm
---
PASS if the reply insists on reproducing the problem and identifying a root cause before
changing code, and says a regression test should fail before the fix is applied.
FAIL if the reply proposes a code change immediately, or suggests adding a guard or null
check without first establishing why the value is wrong.
