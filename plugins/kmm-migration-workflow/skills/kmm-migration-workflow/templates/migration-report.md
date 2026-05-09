<!-- TEMPLATE: copied to <repo>/kmm/<scope>/migration-report.md by specify-phase -->
<!-- Forensic record of every deviation from spec or plan. Survives the migration; reviewed at /kmm-verify; gates pr-phase. -->

# Migration report — [scope-name]

## How this works

Every deviation from `spec.md` or `plan.md` is recorded here, numbered and dated. Status transitions require explicit user approval (recorded inline). At `pr-phase` time, every entry must be `CLOSED`, `RATIFIED`, or `SUPERSEDED` — no `OPEN` deviations may ship.

Status meanings:

- **OPEN** — deviation taken; resolution path not yet executed
- **CLOSED** — deviation resolved per the closure path; no longer affects code
- **RATIFIED** — deviation accepted as a permanent part of this migration; user approved
- **SUPERSEDED** — replaced by a later deviation; the new entry references this one

## Closure types (for auto-close by /kmm-verify)

Every `OPEN` deviation declares a structured closure type so `/kmm-verify` can auto-close it deterministically when the condition is met. Free-form English closure paths are NOT auto-closed.

| Type | Shape | Auto-closed when |
|---|---|---|
| `grep:zero` | `pattern: "<regex>", scope: "<dir-or-file-path>"` | `grep -r <pattern> <scope>` returns zero matches |
| `grep:present` | `pattern: "<regex>", scope: "<dir-or-file-path>"` | `grep -r <pattern> <scope>` returns ≥1 match |
| `binding:present` | `type: "<TypeName>", module: "<path-to-DI-module>"` | grep finds a Koin binding (`single`/`factory`/`scoped`) for the type in the module |
| `test:exists` | `fqn: "<fully.qualified.TestClass.testName>"` | the test source declares the named function |
| `commit:present` | `message-fragment: "<text>"` | `git log` finds a commit on the worktree's branch with the fragment in its message |
| `manual` | (no payload) | never auto-closed; user must change status to `CLOSED` or `RATIFIED` explicitly |

`RATIFIED` is set at deviation creation time when the user explicitly accepts the change as permanent — never auto-promoted from `OPEN`.

## Entries

### D-1 — [Title, one line]

- **Status:** OPEN | CLOSED | RATIFIED | SUPERSEDED
- **Date:** [ISO]
- **Principle bumped:** [§N: Principle name] | "ratified product decision"
- **Root cause:** [one paragraph — what made the deviation necessary; the constraint that forced it]
- **Closure:** `{ type: "<closure-type>", <type-specific fields> }` — structured form, see Closure types table above
- **Approval:** [user message paraphrase + commit reference if applicable]
- **Closed-by:** [populated at auto-close time: `auto-closed by /kmm-verify on <ISO>: <verification result>`, or `manual close by user`]

### D-2 — [Title]

[same structure]

### D-N

[same structure]

## Summary

[populated at /kmm-verify time]

| Status | Count |
|---|---|
| OPEN | 0 |
| CLOSED | 0 |
| RATIFIED | 0 |
| SUPERSEDED | 0 |

[At pr-phase time, OPEN must be 0.]
