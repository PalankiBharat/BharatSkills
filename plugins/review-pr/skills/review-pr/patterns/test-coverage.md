# Test Coverage Patterns

**Don't flag a missing test case without tracing a reachable code path.**
Flagging an untested state you can't prove is reachable from any caller is noise. Before raising a missing test, check: can an actual caller produce this input?

**Test plan checkboxes are claims — verify them against the diff.**
A checked `[x]` in the PR description means the test exists *in this PR*. Cross-check against the diff. If the file is missing, it's a blocker.

**Each caught error code needs a test case.**
For every error code intentionally swallowed, there should be a test that it returns the fallback. For every code that rethrows, there should be a test that it propagates.

**Test the highest data-risk path in every diff, not just the most changed file.**
Ask: "which path, if wrong, would corrupt or lose data?" That path needs a test regardless of how few lines it is.

> Signal: a new early-return or skip-write path (e.g. `tryGetSettings() ?: return`) that bypasses a write to persistence — no test means the invariant is unverified.
