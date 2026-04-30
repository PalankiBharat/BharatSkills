# Orchestrator Diff-Grep — Deterministic Sanity Check

> The migrator self-audits before emitting `STATUS: DONE`. The orchestrator
> trusts the audit, but runs ONE deterministic grep pass against the diff
> as a tripwire for dishonest checklists. No LLM call — pure grep, runs
> in milliseconds, costs ~0 tokens.
>
> If any pattern below matches in the diff, the orchestrator overrides
> the migrator's `DONE` verdict, marks the dispatch `ISSUES_FOUND` with
> the matching pattern named, and re-dispatches the migrator with the
> violation in the prompt.

`applies_to: [orchestrator]`
`concerns: [post-dispatch-verification]`

## Contents

- [When the grep runs](#when-the-grep-runs)
- [Pattern set](#pattern-set)
- [Override behaviour](#override-behaviour)
- [Why this is sufficient](#why-this-is-sufficient)

## When the grep runs

After every dispatch returning `STATUS: DONE` from a code-producing
subagent (`10_migrator`, `14_ios_porter`, `escape_hatch_seam_inserter`,
`escape_hatch_rebase_baseline`).

Invocation:

```bash
git diff <baseline-commit>..HEAD -- 'src/commonMain/' 'src/iosMain/' \
  | grep -nE '<pattern>'
```

Each pattern below is run independently. The orchestrator captures the
matches per pattern and decides per the override rule.

## Pattern set

The grep set is intentionally narrow. Only patterns that are both
unambiguous and high-signal — every match is a real failure.

| ID | Pattern (extended regex) | What it catches |
|---|---|---|
| G01 | `^\+import (java\|javax)\.` (commonMain only) | JVM-only stdlib import survived in commonMain. |
| G02 | `^\+.*\bR\.(string\|drawable\|dimen\|plurals\|color\|raw\|menu\|layout\|id\|array)\b` (commonMain only) | Android `R.*` resource access survived in commonMain. |
| G03 | `^\+import androidx\.compose\.ui\.res\.` (commonMain only) | Android-only Compose resource accessor used in commonMain. |
| G04 | `^\+import (android\|androidx)\.(?!compose\\|lifecycle\\|navigation)` (commonMain only) | Android platform import survived in commonMain (carve-out: multiplatform-aliased Compose / Lifecycle / Navigation namespaces). The exact carve-out list is researcher-confirmed; orchestrator's grep skips lines matching the carve-out. |
| G05 | `^\+.*\b(freeze\\|ensureNeverFrozen\\|@SharedImmutable\\|FreezableAtomicReference)\b` | Deprecated freezing API introduced. |
| G06 | `^\+.*//\s*(TODO\\|FIXME\\|XXX\\|HACK)\b` | New TODO / FIXME / XXX / HACK comment introduced (Law 09). |
| G07 | `^\+import (io\.reactivex\\|rx\.)` (any path) | RxJava import added (Precondition D — should have been replaced). |
| G08 | `^\+import org\.junit\.` (commonTest only) | JVM-only test import survived in commonTest. |
| G09 | `^\+expect class\b` (without project's recorded opt-in flag in build.gradle.kts) | `expect class` declared without the documented opt-in. Orchestrator runs this only if the project's Gradle config doesn't list the current opt-in flag (researcher records the flag in `findings.md`). |
| G10 | `^\+actual typealias\b` (commonMain only) | `actual typealias` placed in commonMain (it belongs in a platform actual site). |
| G11 | Any change under `**/snapshots/`, `**/screenshots/`, `**/goldens/`, `kmm_migration/baseline/<feature>/` (Law 02) | Silent baseline modification. |

The patterns are intentionally conservative — false positives rare,
false negatives possible. The migrator's full self-audit checklist
(`references/migrator_self_audit_checklist.md`) catches the rest;
the grep is just a tripwire for dishonest verdicts.

## Override behaviour

Per pattern match:

1. Orchestrator records the match (file, line, pattern ID, matched text).
2. Orchestrator overrides the dispatch verdict to `STATUS: ISSUES_FOUND`.
3. Orchestrator re-dispatches the migrator with a prompt naming the
   matching pattern(s) and the file:line evidence — instructing the
   migrator to fix and re-run its own checklist.
4. The override counts as one fix cycle for the three-strike protocol
   (so two overrides on the same batch → escalation).

If the migrator's prior dispatch report explicitly justified a match
(e.g., G02 matched a line that's actually inside a comment or a string
that was kept on purpose with documented reason), the orchestrator
checks the justification — if present and the matched line is the
named exception, the override is suppressed. Otherwise, override stands.

## Why this is sufficient

The migrator self-audit checklist already covers ~30 mechanical checks
across 6 sections. The grep here is NOT a replacement — it's a tripwire
specifically for the case where the migrator's checklist transcript
says PASS but the diff disagrees.

This is empirically the highest-risk failure mode of LLM-driven
migrations: the agent reports success because it's been instructed to,
not because the work is actually done. A small deterministic check at
the orchestrator boundary catches dishonesty without the cost of a
second LLM dispatch.

The grep pass takes < 1 second on a typical diff and burns no model
tokens. If a project's diff exceeds the simple greps' performance
(unlikely), the orchestrator runs the patterns one at a time rather
than in one combined invocation.
