# Code Graph Protocol

Read this before any file enumeration, consumer lookup, dependency tracing, or impact analysis. The project's `code-review-graph` MCP tools are faster, cheaper, and more accurate than `Grep` / `Glob` / `Read` for these tasks. **Use the graph first.** Fall back to `Read` / `Grep` only when the graph genuinely doesn't cover.

## Freshness check (run at plan-phase step 0)

1. `list_graph_stats_tool` → capture `Last updated`.
2. `git -C <worktree> log -1 --format=%ai` → HEAD commit time.
3. If `Last updated` < HEAD time (or `never`), call `build_or_update_graph_tool` with `postprocess="full"`. Minimal mode skips cross-file import-edge resolution and silently misleads the planner.
4. Re-call `list_graph_stats_tool`. If still stale, log warning in `findings.md` and fall back to `Read`/`Grep`.

Print one line: `Graph: fresh` / `Graph: refreshed` / `Graph: stale, falling back`.

## Common tasks → graph tool

| Task | Tool | Args |
|---|---|---|
| Find class/function by name or keyword | `semantic_search_nodes` | `query="<name>"` |
| Callers of a function | `query_graph` | `pattern="callers_of"`, `node="<qualified-name>"` |
| Callees of a function | `query_graph` | `pattern="callees_of"`, `node="<qualified-name>"` |
| Importers of a file | `query_graph` | `pattern="imports_of"`, `node="<file-path>"` |
| Tests for a function/file | `query_graph` | `pattern="tests_for"`, `node="<qualified-name>"` |
| Blast radius | `get_impact_radius` | `node="<qualified-name>"` |
| Architecture overview | `get_architecture_overview` | (no args) |
| Detect changed nodes since baseline | `detect_changes` | (uses graph state) |
| Review-friendly source snippets | `get_review_context` | `node="<qualified-name>"` |

## Plan-phase mapping

1. **Enumerate in-scope files**: if user gave file paths, accept them. If only an entry point: `query_graph(callees_of=<entry-point>)` recursively until stable.
2. **Public API per file**: `get_review_context(<file>)` — token-efficient vs. full `Read`.
3. **External dependencies**: `query_graph(callees_of=<file>)`, filter for callees outside the in-scope list.
4. **Consumers**: `query_graph(callers_of=<file>)` — the `Consumers` field.
5. **Dependency DAG**: walk `callers_of` / `callees_of` between in-scope files.

## Verifier mapping

1. **Plan-vs-reality**: `detect_changes` returns changed nodes since `baseline-locked-sha`. Compare against the in-scope list.
2. **Public API match**: `get_review_context(<migrated-file>)` vs. `Public API` field of migration-guide.
3. **Library-swap check**: `semantic_search_nodes(query="<old-library-package>")` should return zero hits in `commonMain/`.
4. **Out-of-scope changes**: `detect_changes` lists every changed file; filter against in-scope and consumer lists.

## When to fall back

- File not parsed by Tree-sitter (rare for Kotlin).
- Need raw text content the graph doesn't expose.
- Graph stale despite refresh.
- Searching for string literals or comments (the graph indexes structure, not strings — use `Grep`).

When falling back, note in `findings.md` why.

## What NOT to do

- Do not `grep -r` to "double-check" graph results.
- Do not `Read` an entire file when `get_review_context` returns the snippet.
- Do not invoke `get_architecture_overview` for a bounded 5-file scope.
