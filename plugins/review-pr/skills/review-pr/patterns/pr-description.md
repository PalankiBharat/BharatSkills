# PR Description Patterns

**Description must explain WHY and WHAT.**
A good PR description has: (1) the *why* — the motivation or problem being solved, not just "fixes bug"; (2) the *what* — a clear summary of what changed so a reviewer knows where to look. Flag if either is missing.

**Description must match the code.**
If description says "catches X and Y" but code also catches Z, flag it — either description is wrong or code has a stray case. Cross-check every claim in the description against the diff.
