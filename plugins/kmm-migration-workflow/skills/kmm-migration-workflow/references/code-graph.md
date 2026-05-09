# Code Graph Protocol

Read this before any file enumeration, consumer lookup, dependency tracing, or impact analysis. The project's `code-review-graph` MCP tools are faster, cheaper, and more accurate than `Grep` / `Glob` / `Read` for these tasks. **Use the graph first.** Fall back to `Read` / `Grep` only when the graph genuinely doesn't cover what you need.

## Freshness check (run at plan-phase step 0)

Graph staleness causes silent wrong answers. Before any graph-first reads, check freshness:

1. `list_graph_stats_tool` → capture `Last updated`.
2. `git -C <worktree> log -1 --format=%ai` → HEAD commit time.
3. If `Last updated` < HEAD time (or `never`), call `build_or_update_graph_tool` with `postprocess="full"`. **Use full, not minimal.** Minimal mode skips cross-file import-edge resolution; `query_graph(importers_of=…)` and `query_graph(callers_of=…)` will return empty or partial results in minimal mode and silently mislead the planner. Full takes longer (~tens of seconds for a few-thousand-file repo) but produces complete edge data. The cost is one-time per plan-phase invocation.
4. Re-call `list_graph_stats_tool`. If still stale, log warning in `findings.md` and fall back to `Read` / `Grep`.

A one-liner reports the result: `Graph: fresh` / `Graph: refreshed` / `Graph: stale, falling back`. The completeness-verifier (`/kmm-verify`) re-checks at audit time — falling back during planning is allowed; falling back during verify means the audit is weaker and gets flagged.

## Why graph-first

- **Token efficient.** Graph queries return structured nodes and edges; `Read` returns whole files (or chunks of them).
- **Accurate.** The graph is built from Tree-sitter parses; it knows what's a class declaration vs. a string literal mentioning the class name. Grep can't.
- **Holistic.** One `query_graph` call gives you all callers/callees/imports of a symbol across the repo. Achieving the same with `Grep` requires multiple invocations and manual filtering.

## Common tasks → graph tool mapping

| Task | Graph tool | Args / pattern |
|---|---|---|
| Find a class/function by name or keyword | `semantic_search_nodes` | `query="<name or keyword>"` |
| List every caller of a function | `query_graph` | `pattern="callers_of"`, `node="<qualified-name>"` |
| List every callee of a function | `query_graph` | `pattern="callees_of"`, `node="<qualified-name>"` |
| List every importer of a file | `query_graph` | `pattern="imports_of"`, `node="<file-path>"` |
| Find tests for a function/file | `query_graph` | `pattern="tests_for"`, `node="<qualified-name or file>"` |
| Blast radius of a change | `get_impact_radius` | `node="<qualified-name>"` |
| Architecture overview | `get_architecture_overview` | (no args) — high-level codebase shape |
| Find communities / clusters | `list_communities`, `get_community_tool` | grouping of related code |
| Detect changed nodes since baseline | `detect_changes` | (uses graph state) |
| Get review-friendly source snippets | `get_review_context` | `node="<qualified-name>"` — returns the relevant code, not the whole file |

## Plan-phase mapping

`plan-phase` reads every in-scope file end-to-end. Replace the manual reading pass with graph calls where possible:

1. **Enumerate in-scope files**: if the user gave file paths, accept them. If only an entry point: `query_graph(callees_of=<entry-point>)` recursively until you've walked into a stable set of files. Prefer this over `Grep "import" -r`.

2. **Public API surface per file**: for each in-scope file, `get_review_context(<file>)` returns parsed methods/properties without full file load. If the graph entry is incomplete (rare), fall back to `Read`.

3. **External dependencies**: `query_graph(callees_of=<file>)` — filter for callees outside the in-scope list. These are the candidates for library swaps or scaffolding.

4. **Consumers of in-scope files**: `query_graph(callers_of=<file>)` — every caller across the repo. The result is the `Consumers` field for the file's migration-guide entry.

5. **Dependency DAG**: between in-scope files, walk `callers_of` / `callees_of` to build the topological order. The graph's edge data is authoritative.

## Verifier mapping

`/kmm-verify` cross-references plan vs. reality. Use graph for the structural diff:

1. **Plan-vs-reality for migrated files**: `detect_changes` returns the changed nodes since `baseline-locked-sha`. The completeness-verifier compares this set against the in-scope list.

2. **Public API match**: `get_review_context(<migrated-file>)` returns the actual public surface; compare to `Public API` field of the migration-guide entry.

3. **Library-swap check**: `semantic_search_nodes(query="<old-library-package>")` should return zero hits in any file under `commonMain/`. Faster than `grep -r`.

4. **Out-of-scope changes**: `detect_changes` lists every changed file; the verifier filters against the in-scope and consumer lists from `spec.md`.

## Migrator and test-capturer mapping

When the migrator or test-capturer needs to find consumers of a file (Step 4 of each), use `query_graph(callers_of=<file>)` instead of `grep -rE "import .*<FileName>"`. The graph gives both the file and the line; grep gives only the file.

## Plan-analyzer mapping

`agents/plan-analyzer.md`'s DAG-soundness check (point 8) — use `query_graph` rather than re-reading every in-scope file. Walk imports/callers across the in-scope set; cycles or missing edges show up directly.

## Fallbacks (when graph doesn't cover)

The graph is built from supported file types only. Use `Read` / `Grep` when:

- The file is not parsed by Tree-sitter in this project (rare for Kotlin, but check `list_repos_tool` if uncertain).
- You need raw text content (e.g., reading the body of a function for behaviour analysis — `get_review_context` returns the relevant snippet, but if you need raw chars, fall back).
- The graph hasn't been updated since a recent commit. The project's hooks auto-update, but if there's a sync gap, the graph may be stale. Prefer `detect_changes` to confirm freshness; if stale, fall back.
- You're searching for string literals or comments — the graph indexes structure, not strings. Use `Grep` for literal text matching.

When falling back, note in `findings.md` why the graph wasn't sufficient — useful signal for the project's graph-coverage maintainers.

## What NOT to do

- Do not `grep -r` to "double-check" graph results — the graph is authoritative.
- Do not `Read` an entire file when `get_review_context` returns the relevant snippet.
- Do not invoke graph tools speculatively (e.g., `get_architecture_overview` when the task is bounded to a 5-file scope). Pick the narrowest tool that answers the question.
- Do not bypass the graph because Read is "easier to think about". Token efficiency matters per Constitution-aligned skill design.
