# Hygiene rules

Always loaded. Covers TODOs, stubs, comments, and KDoc.

Cite as `references/rules/hygiene.md#<rule-id>`.

---

### HYG-01 — TODO/FIXME/XXX/HACK markers added by this PR
**Severity:** P1 (NEW files) | P2 (MODIFIED files)
**Pattern:** `TODO`, `FIXME`, `XXX`, `HACK` comment markers added or present in lines this PR introduced or modified. Pre-existing markers in untouched lines don't fire — the attribution gate handles that path.
**Why:** Markers shipped to master become forgotten tech debt. Fix or convert to a tracked issue before merge.
**Suggestion:** Resolve the TODO in this PR, or open a tracked issue and link the issue in the comment.
**Source:** Industry-standard hygiene; team convention. Verify against master — if master has consistent TODO style with linked issues, that's the team convention.

### HYG-02 — Stub function bodies
**Severity:** P0
**Pattern:** `TODO()`, `throw NotImplementedError(...)`, `error("not implemented")`, empty function body where a return value is required, or `// TODO: implement` immediately above a stub return.
**Why:** Shipping unimplemented code paths to master is a runtime time bomb. iOS especially: a `TODO()` in commonMain throws `NotImplementedError`, which without `@Throws` terminates the app.
**Suggestion:** Implement the function. If genuinely deferred, throw a documented exception declared in `@Throws` and gate the code path so it can't execute.
**Source:** https://kotlinlang.org/api/core/kotlin-stdlib/kotlin/-t-o-d-o.html + https://kotlinlang.org/docs/native-objc-interop.html (unhandled exceptions terminate the iOS app)

### HYG-03 — Commented-out code blocks
**Severity:** P2
**Pattern:** more than 2 contiguous `//`-prefixed lines that look like statements.
**Why:** Dead code in comments confuses readers about intent. Git history preserves what was deleted.
**Suggestion:** Delete. If needed for reference, link to the commit hash that contained it.
**Source:** Industry standard; team convention.

### HYG-04 — Obvious comments restating code
**Severity:** P2
**Pattern:** comment whose text is a near-paraphrase of the code on the next line (e.g., `// increment counter` above `counter++`).
**Why:** Adds noise without information.
**Suggestion:** Delete the comment, or replace with a comment explaining *why* (intent) rather than *what* (code).
**Source:** https://kotlinlang.org/docs/coding-conventions.html (Documentation comments)

### HYG-05 — Stale or inaccurate comments
**Severity:** P2
**Pattern:** comment references obsolete behavior, removed parameters, wrong types, or old class/function names. Detect by cross-referencing comment text against current code — do parameter names, type names, function names mentioned in the comment still exist?
**Why:** Stale comments mislead more than no comment.
**Suggestion:** Update or delete.
**Source:** Industry standard; team convention.

### HYG-06 — Missing KDoc on public commonMain API
**Severity:** P1 (if iOS consumes) | P2 (otherwise)
**Pattern:** new or modified public Kotlin declaration in commonMain with no KDoc block.
**Why:** With `-Xexport-kdoc` enabled, KDoc translates to Obj-C doc comments visible in Xcode autocompletion. Without KDoc, iOS developers see undocumented symbols.
**Suggestion:** Add a brief KDoc block. Format: `/** Short description. Use [paramName] for params. */`
**Source:** https://kotlinlang.org/docs/native-objc-interop.html (Provide documentation with KDoc comments) + https://kotlinlang.org/docs/kotlin-doc.html
