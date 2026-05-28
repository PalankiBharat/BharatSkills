# Heatmap Analysis — master-vs-PR diff → affected journeys

The heatmap decides what to parity-test. "No exclusions, thorough" is the rule: every journey
the diff can touch gets a flow. The art is mapping a business-logic diff to *user journeys*,
because that's what we replay on both builds.

## 1. Diff against LATEST master (not the PR's recorded base)

"master latest is the source of truth." The PR's GitHub base can lag behind master, so always
diff against the freshly-fetched tip (`setup-worktrees.sh` already did `git fetch origin master`):

```bash
git -C "$MASTER_WT" diff origin/master..."$PR_LOCAL_BRANCH" --name-status
git -C "$MASTER_WT" diff origin/master..."$PR_LOCAL_BRANCH" --stat
```

## 2. KMM migration diffs look different from feature diffs

A migration PR mostly **moves** code `app/src/main/...` → `shared/src/commonMain/...` (a
ViewModel/UseCase/Repository/Mapper relocated, package unchanged) and rewires DI. So:

- A pure `git mv` with no body change → low *intrinsic* risk, but the journey it powers still
  gets tested, because the move could change initialization order, DI scope, or threading.
- Watch for the move *plus* edits: a renamed import, a changed coroutine dispatcher, an
  `expect`/`actual` split, a serialization annotation dropped in the move. Those are where a
  "behaviorless" migration silently changes a computed value.

| Path moved into | Layer | Typical journey impact |
|---|---|---|
| `shared/.../repository/*`, `*Repository*` | Data | every screen that reads/writes that data |
| `shared/.../usecase/*`, `*UseCase*` | Domain | the feature(s) invoking the use case |
| `shared/.../viewmodel/*`, `*ViewModel*`, `*Presenter*` | Presentation state | the screen bound to it |
| `shared/.../mapper/*`, `*Mapper*` | Transform | wherever the mapped value is shown — **prime spot for a wrong number** |
| `*Module.kt`, DI wiring | Dependency graph | anything the moved binding feeds (can fan out widely) |

## 3. Trace each changed symbol to the screens that show it

```bash
SYM=OrderRepository
# who consumes it (search both trees so a moved symbol's callers are found)
grep -rn "$SYM" --include="*.kt" "$PR_WT/app/src" "$PR_WT/shared/src" | grep -v "/build/"
# DI injection points
grep -rn "@Inject.*$SYM\|$SYM.*@Inject\|single\|factory.*$SYM" --include="*.kt" "$PR_WT"
```
Trace upward until each chain ends at a screen (a `*Screen.kt` / route the user can reach).
List every directly- and transitively-affected screen → those are the journeys.

**Then map each changed use-case to the INTERACTION that invokes it — not just the screen.** This
is what makes the flow exercise the migrated logic instead of only its initial render. Ask "what
does the user *do* to make this code run?"

| Changed symbol (pattern) | Invoking interaction the flow must perform |
|---|---|
| `Get…` / list use-case / repository | change a date-range/filter/selector, switch tab, pull-to-refresh |
| paging `*Source` / pager | scroll the list to the bottom |
| mapper / `*ViewItem` | expand a row / open the detail that renders it |
| `Download…` / `Submit…` use-case | trigger the action and read the resulting confirmation |

A journey row in the heatmap should name its interactions, e.g. *"<list screen> — open, **change
range/filter**, **scroll**, **submit/download**"* — so Phase 3 generates a flow that performs them
all, and parity is checked after each, not just on the landing screen.

## 4. Risk levels (drive ordering, never exclusion)

| Risk | Criteria |
|------|----------|
| 🔴 Critical | order placement/modify/cancel, funds, auth, anything touching money or persisted state |
| 🟠 High | primary journeys (chart, positions, orders, watchlist), shared ViewModel/Repository moves |
| 🟡 Medium | secondary screens, mappers feeding display-only values |
| 🟢 Low | pure `git mv` with byte-identical body, test-only, config |

Everything affected gets a flow; risk only orders the run and frames the report.

## 5. Read-only vs **state-mutating** — the safety classification (BLOCKING)

This runs on a **real prod account**. Classify every affected journey before running:

- **Read-only** — navigate, view chart/positions/funds, open/close sheets, search. Safe to run
  automatically on both devices.
- **State-mutating** — places/modifies/cancels real orders, activates the kill switch, adds
  funds, changes settings server-side. On prod this is **real money / real orders, doubled
  across two devices.**

Mutating journeys must be surfaced at the heatmap gate and run **only on explicit user
confirmation**, with the journey clearly flagged. Default to refusing mutating flows on a
non-test account, or when the market is open, unless the user confirms. Burning a real trade on
a parity run is a self-inflicted P1 — the same spirit as an OTP-budget check, higher stakes.

## 6. The heatmap gate (pause here)

Present, then **stop for approval** before generating/running anything:

```
## Parity heatmap — PR #<n> (<branch>) vs origin/master (<sha>)
Changed files: <count>   |   Affected journeys: <count>

| Journey | Risk | Mutating? | Existing flow? | Plan |
|---|---|---|---|---|
| Watchlist add/remove | 🟠 | no | maestro/... (none) | generate |
| Cancel normal order   | 🔴 | YES | maestro/order_modify_cancel/01 | reuse — needs your OK |
...
Read-only: N journeys (auto-run).  Mutating: M (need your confirmation).
```
The user approves, trims, or excludes mutating journeys, then the run proceeds.
