# Validation Report Format

## Per-iteration report

After each consumer test, produce this report:

```markdown
### Iteration <n> — Prompt: "<prompt>"

| # | Check | Status | Evidence |
|---|-------|--------|----------|
| B01 | <rule> | PASS/FAIL | <cite specific line or text> |
| B02 | <rule> | PASS/FAIL | <cite> |
| M01 | <rule> | PASS/FAIL | <cite> |

**Failures:**
1. B03: <what failed>
   - Evidence: `<exact code or text that violates>`
   - Root cause: <why the skill produced this>
   - Fix: <specific change to make>

**Result:** PASS (all checks) | FAIL (<n> failures)
```

## Evidence rules

- For PASS: Quote the specific code/text that satisfies the check
- For FAIL: Quote the specific code/text that violates the check
- For N/A: Explain why this check doesn't apply to this prompt
- Never mark PASS without evidence — "looks fine" is not evidence

## Reading generated files

Always read the actual generated file, not just the tmux output:

```bash
cat /tmp/skill-tester-workspace/<filename>
```

The file is the ground truth. The tmux output may be truncated or
may show an intermediate version if the consumer made edits.

## Common validation patterns

**Function size**: Count lines between function signature and closing brace
**Naming**: Check if names use domain vocabulary vs generic terms
**Comments**: Search for `//` or `#` that explain WHAT not WHY
**Null returns**: Search for `return null`, `-> None`, `?: null`
**Stepdown**: Verify public/entry functions appear before private helpers
**Section headers**: Search for `// ---` or `// ===` banner comments
