# Om Pipeline — Active Development

## Current State (2026-03-26)

The `om-pipeline` plugin is at `plugins/om-pipeline/` with three commands:

- `om.md` — Master orchestrator, invokes Bramha then Vishnu, handles retry loop (max 2 cycles)
- `om-bramha.md` — Creation phase (stages 1-6): speckit plan, side effects analysis, speckit task breakdown, team execute (parallel agents with clean-code prehook), harsh review, regression analysis
- `om-vishnu.md` — Preservation phase (stages 7-9): generate device test cases (including regression), device testing via phone-driver, bug fix assessment

## Architecture

```
/om → Bramha (stages 1-6) → Vishnu (stages 7-9) → Om decides retry/complete
```

- Bramha outputs `BRAMHA_RESULT:` JSON for Om to parse
- Vishnu outputs `VISHNU_RESULT:` JSON for Om to parse
- Stage 1 uses `/speckit.plan` for full planning workflow (research, data model, contracts, constitution)
- Stage 3 uses `/speckit.tasks` to break enriched plan into phased, dependency-ordered tasks
- Stage 4 executes tasks as a team — parallel `[P]` tasks spawn concurrent executor agents
- Review cycle counter (max 3) is shared between harsh review and regression analysis
- On review/regression rejection, loops back to Stage 3 (re-generates tasks with fix feedback)
- Side effects analysis enriches plan with safeguards before task breakdown
- Regression analysis cross-references stage 2 amendments post-implementation

## User-level install location

`~/.claude/commands/om.md`, `om-bramha.md`, `om-vishnu.md`

After editing files here, re-install with:
```bash
cp plugins/om-pipeline/commands/om*.md ~/.claude/commands/
```

## What was done in the last session

1. Started from monolithic `bramha.md` (6 stages)
2. Added Stage 2 (Side Effects Analysis) and Stage 5 (Regression Analysis) — now 8 stages
3. Added clean-code prehook to executor prompt
4. Fixed hardcoded path to use `$HOME`
5. Split into 3 files: `om.md`, `om-bramha.md`, `om-vishnu.md`
6. Installed at user level (`~/.claude/commands/`)
7. Added to this repo as `plugins/om-pipeline/`
8. Updated `marketplace.json` and `README.md`

## What's next (potential)

- Test the full pipeline end-to-end
- Consider whether Bramha/Vishnu should be Agent calls instead of Skill calls from Om
- Add install script to the plugin
- Add story-breakdown integration before Stage 1
