# Om Pipeline — Active Development

## Current State (2026-04-03)

The `om-pipeline` plugin is at `plugins/om-pipeline/` with three commands:

- `om.md` — Master orchestrator, invokes Bramha then Vishnu, handles retry loop (max 2 cycles)
- `om-bramha.md` — Creation phase (stages 1-6): speckit specify + clarify + plan, side effects analysis, speckit task breakdown, team execute + build gate, harsh review, regression analysis
- `om-vishnu.md` — Preservation phase (stages 7-9): generate device test cases (including regression), device testing via phone-driver, bug fix assessment

## Architecture

```
/om → Bramha (stages 1-6) → Vishnu (stages 7-9) → Om decides retry/complete
```

- Bramha outputs `BRAMHA_RESULT:` JSON for Om to parse
- Vishnu outputs `VISHNU_RESULT:` JSON for Om to parse
- Stage 1 uses `/speckit.specify` → `/speckit.clarify` → `/speckit.plan` (full spec-to-plan workflow)
- Stage 3 uses `/speckit.tasks` to break enriched plan into phased, dependency-ordered tasks
- Stage 4 executes tasks as a team — parallel `[P]` tasks spawn concurrent executor agents
- Stage 4.5 BUILD GATE verifies project compiles before review
- Three independent fix cycle counters (each max 2): BUILD_FIX_CYCLE, REVIEW_FIX_CYCLE, REGRESSION_FIX_CYCLE
- On review rejection: generates targeted FIX tasks from feedback (not full task regeneration)
- On regression found: generates targeted REGFIX tasks (not full task regeneration)
- Side effects analysis enriches plan.md on disk with safeguards before task breakdown
- Regression analysis cross-references stage 2 amendments post-implementation
- Om passes `spec_dir` to Bramha on retry cycles so SPEC_DIR is always available

## User-level install location

`~/.claude/commands/om.md`, `om-bramha.md`, `om-vishnu.md`

After editing files here, re-install with:
```bash
cp plugins/om-pipeline/commands/om*.md ~/.claude/commands/
```

## What's next (potential)

- Test the full pipeline end-to-end with the new specify + clarify + plan flow
- Consider whether Bramha/Vishnu should be Agent calls instead of Skill calls from Om
- Add install script to the plugin
- Update Vishnu to consume `spec_dir` from BRAMHA_RESULT for richer test generation
