# Blast Radius Patterns

**Flag changes to widely-used public/internal APIs.**
If a changed function is imported by 5+ callers or lives in a `core/`, `common/`, or `shared/` module — flag as high blast-radius. Note the approximate caller count if inferrable from the diff context.

**Flag silent failures over loud ones.**
If a bug in this change would produce wrong data silently (wrong state persisted, silent data loss, incorrect UI state shown) rather than crashing loudly — flag as higher severity. Silent failures are harder to detect and debug in production.

**Flag data loss / data corruption paths as blockers.**
Any change where a bug could overwrite, delete, or corrupt persisted user data (DB writes, preference writes, network mutations) — flag as `blocker`. Wrong-data-shown or crashes → `non-blocking`. Cosmetic → `nit`.

**Flag persistence-format changes without rollback.**
A change to a DB schema, serialized data format, or API contract with no reverse-migration or backwards-compatible fallback — flag as `non-blocking` (or `blocker` if migration is irreversible). Note: "rollback path exists" = feature flag, or additive-only change, or migration is reversible.

**Flag high-impact changes without a feature flag.**
A change to core business logic, data persistence, or networking that is live for all users immediately and has no kill switch — flag and note the rollback gap. Explicitly note: "No feature flag — cannot partially roll back."
