<!-- TEMPLATE: copied to <repo>/kmm/<scope>/findings.md by plan-phase -->
<!-- Research, decisions, version pins. Live-sourced — every entry has a citation and date. -->
<!-- Untrusted external content goes here, never in plan.md. -->

# Findings — [scope-name]

## Decisions made during planning

Every architectural / library choice with options considered, the chosen path, and the rationale. Survives `/clear`; the migrator and verifier subagents read this when they need to know *why*.

| Decision | Options considered | Chosen | Rationale | Source | Verified |
|---|---|---|---|---|---|
| [e.g., Networking library for shared code] | [Ktor 3.x; project-specific HTTP wrapper] | [Ktor 3.0.3] | [official KMP support; matches consumer toolchain floor] | [URL or context7-id] | [ISO date] |
| ... | ... | ... | ... | ... | ... |

## Library versions

Every library swap with the verified version. The migrator uses these versions exactly — no re-research at execution time.

| Library | Version | Source | Last verified | Notes |
|---|---|---|---|---|
| [Ktor Client] | [3.0.3] | [https://ktor.io/docs/welcome.html] | [2026-05-08] | [OkHttp engine on Android, Darwin on iOS] |
| ... | ... | ... | ... | ... |

## Compatibility floor

Consumer-side toolchain pins. The migrated code must not require versions higher than these.

| Component | Floor | Source |
|---|---|---|
| Kotlin | [version] | [path to consumer's gradle setup] |
| Gradle | [version] | [path] |
| Android Gradle Plugin | [version] | [path] |
| Xcode | [version] | [iOS consumer's CI config or README] |
| ... | ... | ... |

## Gotchas

Project-specific issues found while reading the codebase that will affect migration. Non-obvious things the migrator and consumers should know.

- [e.g., "session_token vs x-request-token: server expects x-request-token; the Android code uses the former — bug preserved per §6, logged as deviation D-N"]
- ...

## Research notes (free-form)

Library docs, working-group threads, GitHub issues, vendor blog posts that informed the plan. Untrusted external content lives here, not in `plan.md`.

[paste links + relevant excerpts. each excerpt has the URL it came from and the retrieval date. flag any training-data-derived claim with `⚠ TRAINING DATA — VERIFY` and resolve before tasks-phase.]

## Live-source audit

[populated at plan-phase time and re-checked at /kmm-verify]

- All library versions: live-sourced ✓
- All API patterns: live-sourced ✓
- All config snippets: live-sourced ✓
- Drift-phrase scan in this file: clean ✓

[any failure here is a Constitution §3 / §4 violation — the orchestrator escalates.]
