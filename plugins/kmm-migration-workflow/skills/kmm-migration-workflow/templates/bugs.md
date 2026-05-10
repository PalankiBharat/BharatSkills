<!-- TEMPLATE: copied to <session-dir>/bugs.md at /kmm-qa session start -->
<!-- Per-session bug log. Each entry is the qa-debugger agent's contract for diagnose + apply-fix. -->

# QA bugs — [session-name]

## How this works

Every bug pinpointed during a QA session lands here as a numbered entry. The entry IS the architecture for that fix (Constitution §1: architecture before code). `qa-debugger` writes the proposed entry in `mode: diagnose` (status `PROPOSED`), the orchestrator promotes it to `OPEN` after user approval, and `qa-debugger` applies it verbatim in `mode: apply-fix` (status flips to `FIXED` on success).

Reading this file alone — without conversation history — must recover full context for every bug fix in the session. That's the §12 contract.

Status meanings:

- **PROPOSED** — `qa-debugger mode: diagnose` wrote the entry; orchestrator has not yet asked the user for approval
- **OPEN** — user approved the proposed fix; `qa-debugger mode: apply-fix` may now run
- **FIXED** — fix applied, failing test wrote and went RED, fix made it GREEN, no regressions, targets compile clean
- **RATIFIED** — user declined the fix in this session (e.g., wants to keep observing across iterations); not a bug-the-skill-will-act-on
- **SUPERSEDED** — replaced by a later entry that subsumed this one (rare; user-driven)

## Session metadata

- **Session:** [session-name]
- **Anchor:** kmm-scope:[scope] | standalone
- **Baseline SHA:** [git rev-parse HEAD at session start]
- **Started:** [ISO]
- **Device:** [device.label from qa-config.json]
- **qa-config:** [path to qa-config.json]

## Entries

### B-1 — [Title, one line]

- **Status:** PROPOSED | OPEN | FIXED | RATIFIED | SUPERSEDED
- **Reported-at:** [ISO]
- **User description:** [verbatim from user — what they saw on screen + symptom]

#### Logcat excerpt

```
[3–10 raw lines from logcat — the topmost stack frames pointing into project code, plus the FATAL EXCEPTION header line. Empty for visual / logic-only bugs; replace with "(no logcat — bug is visual / logic-only)".]
```

#### Root cause

- **File:** `[file path]`
- **Line:** [n]
- **Why:** [one paragraph — what the code does, why that's wrong given the user's description, citation to the source line]

#### Fix path (Constitution §7)

- **Path:** surgical | refactor
- **Rationale:** [one line — for surgical: "isolated to the named line, no naming/structure change". For refactor: cite the §7 clean-code violation it addresses + the file boundary]

#### Fix diff spec (qa-debugger's verbatim contract)

```
Modify ([file]:[line-or-range]):
  Before:
    [exact current line(s)]
  After:
    [exact replacement line(s)]
```

(Or `Remove` / `Add` entries — same shape as `migration-guide.md` Diff specifications.)

#### Test to write

- **Test name:** [camelCase]
- **Test file:** [path under commonTest/ or jvmTest/ or the project's test source set]
- **Test body:**
  ```kotlin
  @Test fun [testName]() {
      [verbatim Kotlin source — black-box, hand-rolled fakes, deterministic]
  }
  ```
- **Expected (RED before fix):** [one line — the assertion that fails on current code]
- **Expected (GREEN after fix):** [one line — same assertion passes after the diff spec is applied]

#### Closure

- **Fixed-at:** [ISO — populated by orchestrator when QA_FIX_COMPLETE returns]
- **Fixed-by-test:** [test fqn — populated at FIX_COMPLETE]
- **verify-red:** proven | not-yet-run

#### Block (only when status=OPEN with QA_FIX_BLOCKED)

- **Block-reason:** [one-line reason from qa-debugger]
- **Surfaced-at:** [ISO]

### B-2 — [next entry, same structure]

…

## Out-of-band notes

Use this section for QA observations that are NOT bugs — performance impressions, UX nits, behaviour the user noticed but didn't request a fix for. These do not become entries in the numbered list above. They survive the session as context for the user's next decisions; they are not the qa-debugger agent's contract for anything.

- [free-form line]
- [free-form line]
