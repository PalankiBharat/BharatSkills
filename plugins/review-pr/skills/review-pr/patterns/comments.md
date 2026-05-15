# Comment Quality Patterns

**Comments should explain WHY, not WHAT.**
If a comment describes what the code does (which well-named identifiers already do), flag it as redundant. Only add a comment when the WHY is non-obvious: a hidden constraint, a subtle invariant, a workaround for a specific bug.

**Flag misleading comments.**
A comment that contradicts the code (e.g. "unreachable after the extrapolation path lands" but the function is still reachable) is worse than no comment — it actively misleads future readers. Flag any comment that makes a claim the diff disproves.

**Flag commented-out code.**
Dead code in comments is noise. It should be deleted; git history preserves it if needed.

**Outdated comments.**
A comment referencing a class, method, or behaviour that no longer exists in the diff — flag for update or removal.
