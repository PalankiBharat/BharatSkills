# Pre-ship Authoring Checklist

Run before every release.

## Structural

- [ ] Directory is `skills/kmm-migration/` (kebab-case).
- [ ] Entrypoint is `SKILL.md` (uppercase).
- [ ] Frontmatter populated per spec §20.2; description ≤1024 chars.
- [ ] SKILL.md body ≤500 lines.
- [ ] Every reference file >100 lines has a Contents TOC.
- [ ] No reference-to-reference links (one level deep only).
- [ ] No `@path` force-loads anywhere.

## Language

- [ ] Discipline-language audit passes (no "consider"/"try to"/"probably"
  in any law or dispatch prompt).
- [ ] Every dispatch prompt has `requires_success_criterion: true` and
  a concrete success criterion in the caller prompt.

## Testing

- [ ] RED pressure scenarios exist for Laws 1, 2, 9, 12, 13, 14 — minimum 3
  per law.
- [ ] Scenarios tested on Haiku, Sonnet, Opus.

## Self-contained

- [ ] No `superpowers:*` invocations — three patterns inlined as native reference files.
- [ ] `worktree_setup_protocol.md`, `verification_protocol.md`, `root_cause_protocol.md`
  present in `references/` and referenced by the correct dispatch templates.

## Scoping

- [ ] `allowed-tools` and `paths` frontmatter fields scoped correctly.
- [ ] `kmm_migration/` artifact directory is git-trackable at repo root
  (not under `.kmm-migration/`).

## Operational

- [ ] State survives `/clear` — tested by clearing mid-migration and
  verifying resume works.
- [ ] Skill dispatches itself cleanly when the user types
  `/kmm-migration <feature>`.
