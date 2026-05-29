# Phase A — Diagnostic

**Purpose.** Produce `plan.md` — the architectural design doc that answers every "how" question before Phase B (uniform structural relocation + baselines) and Phase D (KMM-ification) begin. Per-file analysis (surface, deps, seam strategies, Phase D plan, risks) + cross-file synthesis (Phase D migration order, DI plan, aggregated risk register, foundation `expect`/`actual` plan).

**No code written, no tests written.** Just the design that makes Phase B and D mechanical.

**Inputs:** `scope.md`, `plan.md` (if resuming), `project.md`, `coverage.md`, cached searches in `.kmm/searches/`, `references/expect-actual-boundaries.md` (seam-strategy rubric).

---

## Sub-phases

### 1. Library-substitution decisions (discussion-first)

Before any bulk search, lock the library substitution direction for every Android-only dep in scope. Searches that run against a moving target produce subagent context drops (a subagent doesn't see the resolved decision and re-derives it incorrectly).

- Skill enumerates candidate library substitutions from Phase 0 scope (Retrofit, Joda, Gson, Paging <3.5, etc.).
- For each, present as a **discrete user decision** in plain language (per SKILL.md Decision routing): *"Found Retrofit usage in 7 files. Plan to substitute with Ktor (works on iOS). Confirm direction?"* **Dependency change/replacement/version decisions are never auto-decided — always routed to the user** (SKILL.md general rule).
- User confirms / pushes back / picks a different target lib.
- **Version-exists + Kotlin-compatibility check (mandatory, before locking).** For each confirmed target library + version, verify against reality, anchored to the repo's pinned Kotlin version: (a) the exact version **exists** (Maven Central / repo metadata — `curl` the `maven-metadata.xml` or `./gradlew :<dest>:dependencyInsight --dependency <lib>`), and (b) it's **ABI-compatible with the repo's Kotlin version**. *Why: a prior session locked GitLive `2.5.0` (which doesn't exist), and the chain Kotlin-version → Room-version → GitLive-version → needed-API only unravelled deep in Phase D. Aspirational versions cost time proportional to how far the migration has progressed.* Record the verified version in `plan.md`. Phase D re-checks at entry (cheap guard against drift).
- **Transitive-consumer scan (mandatory, before locking).** For each confirmed substitution target, dispatch a Haiku subagent to enumerate transitive consumers — libraries in the gradle classpath that *depend on* the substituted library and may break under the new version. Use `./gradlew :<dest>:dependencyInsight --dependency <lib>` (or `./gradlew dependencies | grep <lib>`). Flag any version constraint mismatch or binary-compat risk discovered. Each flagged transitive consumer becomes a row in `plan.md`'s risk register with proposed handling: (a) tolerate (compatible across versions), (b) bump together (in-scope addition), (c) defer (declare out-of-scope, accept the implication). User decides per row. **Out-of-scope file rewrites caused by transitive bumps are part of the migration's blast radius — make them visible at planning time, not at Batch N when a build fails.**
- Confirmed substitutions land in `plan.md` decisions log AND feed the per-file `lib-swap` classifier in sub-phase 2 (Path A — contract baseline / Path B — defer to Phase D / `none` — no swap).
- **No bulk search until every lib-swap direction is locked.** This protocol is the cause-of-truth for subagent prompts in sub-phase 2.

### 1.5. HTTP client parity audits (when an HTTP-client substitution is locked)

Triggered if sub-phase 1 confirmed any HTTP-client substitution (Retrofit→Ktor, OkHttp→Ktor, OkHttp engine swap, etc.). Two audits, both mandatory; both produce plan.md tables Phase D applies literally and Phase F.3 verifies via runtime network capture.

**Per-service timeout parity audit (F1).**
- For each HTTP client interface in scope, enumerate the per-service timeout config (connect / read / write / call) from the existing builder, interceptor stack, or service-key-keyed dispatch.
- Map to the new client's timeout config. plan.md lists, per service:
  ```
  <service-key>: connectTimeoutMillis=<X>, requestTimeoutMillis=<Y>, socketTimeoutMillis=<Z>
  ```
- Values sourced **verbatim** from pre-migration code — not invented. Cite source path + line.
- **Empty timeout install on the new client is a P0 risk.** Defaults vary by underlying engine (OkHttp's 10s socket-read default has caused user-visible 500s on slow endpoints in prior migrations); the migration must preserve the pre-migration values or document a deliberate deviation under a migration-exception.

**Server-registration parity audit (F2).**
- For each new RemoteStore introduced (or any RemoteStore whose target host shifts), identify the project's shared HTTP client config object. Consult `project.md` `networking.shared_client_config.object_name` if captured at Phase 0; otherwise grep for `*Configuration` / `*Client` factory and capture the name in project.md (diff-confirm).
- Confirm: (a) the target host is registered in that config object, (b) per-flavor build-time host constants exist for the host (per `project.md` `networking.shared_client_config.host_constant_convention`).
- plan.md lists each new/changed host with its config-object entry name and the build-time constant name(s). Missing registration = a P0 risk in the register.

Both audits feed `plan.md`'s risk register and become mandatory checkpoints in Phase F.3.

### 1.6. Platform-ownership decisions (BLOCKING — resolved here, never deferred to Phase D)

Some architectural choices determine the *shape* of the whole migration and are ruinous to discover mid–Phase D. Both prior sessions paid for this: one rewrote database entities after a "Room-everywhere vs platform-owned storage" pivot landed at the D.1 boundary (~2h of rework); the other thrashed 4 round-trips + a full revert over where DI-framework annotations live. These are knowable now.

Resolve and record each (this is a Phase A completion gate; Phase D will not start without it):
- **Storage ownership** — does each platform own its native DB (native-per-platform: e.g., Android keeps ObjectBox/Room-Android, iOS gets its own, commonMain holds plain data classes + interfaces), or is storage shared (e.g., Room KMP / SQLDelight everywhere)? This gates the entire entity/DAO plan.
- **DI-framework symbol placement** — kept in the app layer (commonMain classes take plain constructor params; the platform DI layer disambiguates), or pushed into shared? Default per the canonical hard-won answer: **keep DI-framework symbols (Hilt qualifiers, etc.) out of `commonMain`; resolve in the app-side providers.**
- **Logging** — which shared logging approach (e.g., injected `ILogger` interface / Kermit), decided once.
- **Catch-all** — any other capability whose platform-ownership is ambiguous → decide it here, not at execution time.

Each is a dependency-adjacent / behavior-shaping decision → routed to the user in plain language with the skill's evidence-based recommendation (SKILL.md Decision routing). Recorded in `plan.md` decisions log; feeds the Phase D batch plan.

### 1.7. Plan validation pass (parallel docs+web sweeps)

After scope and the substitution/platform decisions above are locked, validate the *plan against current ecosystem reality* before committing to Phase A's per-file work. **Runs whenever the plan is non-trivial** — any library swap, new infra dependency, version pin, or iOS-consumption concern arms it; a trivial pure-Kotlin move with zero dependency changes may skip it (announce the skip).

Dispatch 3–4 parallel Context7+web sweeps, one per major decision area (e.g., "Room KMP mechanics + iOS wiring", "GitLive Firestore on iOS", "Kermit + datetime + coroutines"), **plus a mandatory "what's changed in the last 12 months" sweep** for the libraries/SDKs in play. Cache every result to `.kmm/searches/<topic-hash>.md` (30-day TTL) so the next migration reuses it.

*Why this earns its place: in a prior session this pass (~40 min) caught a setting that would have silently cascade-deleted production data, a library package rename, an SDK sunset deadline, and a Kotlin-version prerequisite — none visible to the normal per-file analysis. Its surprises-caught-per-hour is the highest of any planning activity.* Findings that invalidate a locked decision loop back to sub-phase 1/1.6 (re-decide with the user).

### 2. Bulk pattern search (orchestrator)

Based on Phase 0 manifest + locked lib-swap decisions, fire live searches:

- *"KMM migration `<file-type>` patterns 2026"* per file-type category in scope.
- *"Kotlin `<library>` KMM antipatterns"* per non-trivial dep surfaced.
- *"SKIE `<pattern>`"* for Swift-consumption concerns relevant to scope.
- **iOS Swift interop axis (mandatory, per file-type in scope).** Fire three coordinated searches per file-type category present in the manifest: *"KMM `<file-type>` iOS Swift interop patterns 2026"*, *"SKIE `<file-type>` consumption examples"*, *"KMM `<idiom>` iOS pitfalls"* where `<idiom>` is the dominant idiom of that file-type (e.g., for UseCase: suspend / Flow / sealed return / callback param; for Repository: Flow / Result wrapper; for ViewModel: StateFlow / SharedFlow). Same parallel-Sonnet dispatch, same `.kmm/searches/<topic-hash>.md` cache, same 30-day TTL. **This axis is not optional and not deferrable to Phase F** — Phase F verifies what these searches inform at A. The skill cites these results; it does not bake SKIE patterns into its references.
- Context7 lookups for KMM-native library API signatures (current).

Results cached in `.kmm/searches/<topic-hash>.md` — **subagents consume from cache** (per SKILL.md Subagent-mediated exploration; the cache exists for cross-session reuse, not main-context bloat). Future sessions don't re-search.

### 3. Per-file analysis (parallel Sonnet)

**Subagent prompt template — mandatory prefix.** Every per-file analysis subagent dispatch in this sub-phase is prefixed with a `## Resolved decisions (from Phase 0 + Phase A sub-phase 1)` block. The orchestrator **auto-assembles this block once** from `plan.md`'s decisions log (locked substitutions + verified versions + platform-ownership decisions) and reuses it verbatim across every parallel dispatch — never hand-pasted per prompt. Subagents **apply** these decisions, **never re-derive** substitution choices. This prevents the failure mode where one subagent miscalls a file because the deciding context wasn't in its prompt.

**SDK/library KMM-availability — HARD GATE (NON-NEGOTIABLE).** Before any subagent (or the orchestrator) labels a dependency Android-only / `no-equivalent` / `Forces hold`, it MUST verify against the library's **published Gradle module metadata** — the `.module` file / an `iosSimulatorArm64`/`iosArm64`/`iosX64` klib in `~/.gradle/caches`, or `./gradlew :<dest>:dependencyInsight --dependency <lib>`. **How the `:app` consumes it proves nothing about iOS availability.** The per-file analysis entry must **cite the metadata check** behind any "non-portable" verdict; a verdict without the citation is rejected and re-run. When the check is genuinely inconclusive, surface to the user rather than guess (SKILL.md Decision routing). *Repeated failure mode: `mobilenetworkingsdk` was misclassified Android-only three times across two sessions; the gradle-cache klib proved it KMM-published each time, and the user had to correct it.*

**Output schema — enumerated values only (no free-form phrasings).** Parallel analysis subagents drifted across two sessions ("migrate-with-seam", etc.), forcing the synthesizer to normalize. Each per-file entry uses exact enum values: **`Phase D plan` ∈ {`migrate`, `hold`}**, **`lib-swap` ∈ {`path-a`, `path-b`, `none`}**, **iOS interop verdict ∈ {`clean`, `blocked`, `degraded`}**. Reject and re-run any subagent output that invents a value outside these sets.

Per in-scope file:

- **Public surface** — methods, signatures, return types, exceptions, public properties.
- **Direct + transitive deps of concern** — Android-only / has-KMM-equivalent / no-equivalent. Each "Android-only"/"no-equivalent" verdict carries its gradle-metadata citation (per the hard gate above).
- **Classification** — platform-free / -incidental / -essential, with cited justification.
- **`lib-swap` classification** — applies if this file uses any of the libraries locked for substitution in sub-phase 1:
  - **`path-a`** — SUT output is assertable without referencing the old-lib types (use MockWebServer / hand-rolled HTTP fake / date-string outputs / round-tripped objects). Baseline in Phase B survives the swap unchanged. **Default**.
  - **`path-b`** — SUT public surface unavoidably exposes old-lib types (e.g., RemoteStore method returning `Result<T, retrofit2.HttpException>`, DTO whose contract IS its `@SerializedName` annotation surface). Defer baseline to Phase D — tracked in `phase-d-followups.md`.
  - **`none`** — no lib swap touches this file.
  
  Decision rule: if a baseline can be written that compiles unchanged before and after the lib swap → `path-a`. Only otherwise → `path-b`. Bias hard toward `path-a`. See `test-discipline/migration-baselines.md` §Library-substitution.
- **Per-dep seam strategy** for each platform-touching dep:
  - **commonMain-ready** — dep is already KMM-portable (e.g., `kotlinx.datetime`, `kotlinx.serialization`). Migrate as-is.
  - **`expect`/`actual`** — dep needs platform-specific impl behind a common signature.
  - **Interface-and-adapter** — extract interface to commonMain, keep Android impl behind it in androidMain.
  - **Forces hold** — no clean KMM seam this session (e.g., Android-only SDK with no abstraction worth building yet).
  
  **Consult `references/expect-actual-boundaries.md`** for the decision rubric between `expect`/`actual` vs interface-and-adapter (rule of thumb: interface when tests / DI / lifecycle / runtime selection matter; `expect`/`actual` for simple compile-time platform specialization). Pattern lookups inform each — Context7 for API specifics, web search for patterns (per SKILL.md Tooling discipline). No training-data guesses.
- **Phase D plan** for the file:
  - **`migrate`** — every dep has a non-`Forces hold` seam strategy. File will be relocated `androidMain` → `commonMain` in Phase D this session.
  - **`hold`** — at least one dep forces hold. File stays in `androidMain` after Phase B (post-relocation). Promotion deferred to a future session.
- **`expect`/`actual` sketch** if any (for Phase D foundation).
- **File-specific risks** — behavioral-divergence, concurrency, other (iOS interop has its own field below — don't duplicate here).
- **iOS Swift interop assessment** *(applies only to files with `Phase D plan: migrate`; `hold` files skip — they don't reach commonMain this session, so no Swift consumer exists yet).* Sourced from the cached iOS-axis search results (sub-phase 2), **never training recall**. Cite the specific `.kmm/searches/<hash>.md` row that motivates each finding.
  - **Swift consumer view of public surface** — for each public method/property, the expected Swift call site shape (return type, async/await vs completion, optional vs non-optional, exhaustive-switch availability for sealed returns, etc.).
  - **Interop verdict** — exactly one of `clean` / `blocked` / `degraded`:
    - **`clean`** — Swift consumes naturally; no change needed.
    - **`blocked`** — Swift cannot consume, or loses type safety / structured concurrency / type information at the boundary. File **cannot migrate this session without a surface change**.
    - **`degraded`** — Swift consumes but with ergonomic loss (verbose unwrap, flattened companion access, etc.). **Not a blocker. No change made.**
  - **Must-needed refactor** *(only if verdict = `blocked`)* — the minimal surgical signature change that unblocks Swift consumption. Cited to the search hit that motivates it. Refactor **shapes** that may be in scope: return-type shape change (e.g., callback param → sealed return), nullability tightening at the boundary, exception declaration (`@Throws`) for surfaces Swift will call. **Android adapts to the new shape mechanically** — same behavior, new signature. Caller-count grep mandatory (`git grep` / `rg -l` across the entire repo) before the refactor lands in plan.md — same protocol as helper-deletion plan in sub-phase 4. Out-of-scope callers route through the scope-creep options (defer / refactor-in-place / extend-scope / flip-to-hold). The refactor must be **traceable to a cited blocker**, not a designer's preference.
  - **Rejected improvements** — list of iOS-flavored changes the per-file subagent considered and **rejected** because they're polish, not blockers (renames for casing alignment, `kotlin.Result<T>` wrappers for ergonomics, new abstractions introduced for "cleanliness", `@objc` adornments that affect only readability). One line each — proves the rubric was applied. Without this field, the skill drifts toward gold-plating.

  **Must-vs-want rubric (apply strictly):**
  > **iOS-MUST-NEEDED:** Swift compile failure; loss of type information across the boundary (e.g., generic erasure to opaque type); forced unsafe casts on the consumer; uncaught exception surfacing that crashes Swift; structured-concurrency violation at the suspend/Flow boundary; sealed hierarchy reaching Swift as a non-exhaustive opaque type.
  > **NOT iOS-must-needed:** verbose-but-functional Swift call sites; naming preferences; cosmetic readability; ergonomic wrappers like `kotlin.Result<T>` when the function can just return its value or throw a declared exception; "while we're here, let's also..." restructuring.
  > **When in doubt: `degraded` ≠ `blocked`.** Do not migrate by upgrading `degraded` to `blocked` to justify a refactor — the verdict drives the action, not the desired action driving the verdict.

- **SUT test-classpath gaps** — if the SUT compiles against any dep that's `compileOnly` or platform-only (e.g., `retrofit2.HttpException`, `androidx.paging`), record the gap so Phase B's B.0 source-set bootstrap can preempt it (add `testImplementation` early, not retroactively when B.4 compile breaks).
- **Migration-order signal** — what this depends on (informs Phase D ordering for `migrate`-plan files).

### 4. Cross-file synthesis (Opus)

- **Phase D migration ordering** — topological for `migrate`-plan files: leaves first (Models, Mappers), layers up (Repositories, UseCases), Presentation last if in scope. `hold`-plan files don't participate in Phase D ordering.
- **DI module plan** — Koin module structure for destination per profile's DI stance and `test-discipline/index.md` MockK-default rules. Covers both `commonMain` bindings (for migrated files) and `androidMain` bindings (for held files).
- **Aggregated risk register** — dedup risks, group by category, each paired with the Phase B baseline test type that will catch it.
- **Consolidated `expect`/`actual` interfaces** — merge where multiple `migrate`-plan files need the same abstraction (one `Clock`, one `NumberFormatter`, etc.). **≥2-consumer test enforced** — single-consumer abstractions get inlined.
- **Phase D plan reassessment** — any file initially marked `migrate` that synthesis reveals is too risky / iOS-incomplete → flip to `hold` with rationale recorded. Scope itself doesn't change; only the per-file Phase D plan flips. User confirms each flip. **Concrete iOS-blocker trigger:** if a file's iOS interop verdict is `blocked` and its must-needed refactor's caller-count grep surfaces out-of-scope consumers, route through the scope-creep options — **(a) defer** the refactor and flip the file to `hold` (iOS-blocker remains; not migrated this session), **(b) refactor-in-place** if the new shape is binary-compatible at call sites (rare), or **(c) extend-scope** to absorb the out-of-scope callers (user explicit confirmation). The default for unresolved iOS-blockers with out-of-scope ripple is **(a)** — migration that ships Swift-unconsumable code is worse than holding.
- **Helper / foundation deletion plan — caller-count grep mandatory.** For any plan.md action of the form *"delete X helper"* or *"extract from X"* (typically a date-utility, formatter, extension function, or Android-specific helper being superseded by a commonMain abstraction), run `git grep -l '<helper-symbol>'` (or `rg -l`) across the **entire repo** before committing the deletion to plan.md. Count callers; list them by source set / module. If any caller is **outside the migration scope**, the action MUST be downgraded to one of:
  - **(a) Defer** — delete in a follow-up PR once callers migrate. Logged to `phase-d-followups.md` as `helper-deletion-deferred` with caller list. **This is the default.**
  - **(b) Refactor in place** — keep the helper symbol, change its implementation. No deletion this session.
  - **(c) Extend scope** — add the out-of-scope callers to scope.md and re-run Phase 0's dep-walk for them. User explicit confirmation.
  
  No silent "we'll just delete it" — Phase D's scope-creep gate will halt at D.0 if this is skipped. Cheap to verify here; expensive there.
- **Batch dep-direction verifier (D8).** After drafting the Phase D migration ordering, dispatch a Haiku verifier. For each consecutive batch pair `(N, N+1)`, the verifier confirms that no file in batch N references a type defined in batch N+1. Output: either `order verified` (proceed) or a list of cross-batch reverse-direction dep violations with file:line citations (re-order or merge the implicated batches before locking). Cheap pass; catches the class of error where the planner's mental topo-sort drifts from the actual type dependency graph.

### 5. Self-review (skill principle #2 — clean code)

Before presenting:
- Every new interface has ≥2 consumers (or gets inlined).
- No abstractions "just in case."
- No `*Holder` / `*Manager` cruft.
- Self-review notes recorded explicitly:
  > *"Considered `FundsClock` interface but inlined `Clock.System` — single consumer."*

### 6. User review + confirmation

Batched per logical unit (per file, then synthesis). User accepts / edits / rejects each batch. `plan.md` status flips to complete on final confirmation.

### 7. Phase A retro
Before marking Phase A complete, amend `retro.md` with a `## Phase A — Diagnostic (captured YYYY-MM-DD)` section: five-bullet structure per SKILL.md. **Blocking, non-skippable** (per SKILL.md Retro gate).

---

## Mid-phase scope amendment protocol

During per-file analysis, a subagent may surface an in-scope file referencing something **not in scope.md** (e.g., a foundation extension function, a date helper, a model used outside the scoped layer). When this happens:

1. Skill pauses per-file analysis on that file.
2. Present the discovery: *"Found: `<in-scope-file>` references `<symbol>` at `<location>`. Not in scope.md. Add to migration? (y/n)"*
3. If **yes**: amend `scope.md` (additions appended under `## Discovered mid-phase` section with date), regen `plan.md` entry for the new file (run the new file through sub-phase 3 itself), resume Phase A from where it paused. Per-file Phase D plan summary table updated.
4. If **no**: log to `phase-d-followups.md` as `out-of-scope-dependency` with the reference site, to be reconsidered post-migration.

This protocol replaces ad-hoc improvisation when out-of-scope deps surface late. Phase 0 catches the typical case (full dep walk); this catches the residue.

---

## Output: `plan.md`

Living document. Contains:

- Header (status, tasks)
- **Locked library substitutions** (from sub-phase 1) — table: source-lib → target-lib → file count → confirmed-by-user date.
- Cached live-search results (patterns, antipatterns, KMM-native API references)
- Per-file analysis (one entry per file with the fields above, including `Phase D plan: migrate / hold`, `lib-swap: path-a / path-b / none`, and for `migrate` files the `iOS Swift interop assessment` block — verdict + Swift consumer view + must-needed refactor (if `blocked`) + rejected improvements — each with search-cache citations)
- **Per-file iOS interop summary table** (only `migrate` files) — file → verdict (`clean`/`blocked`/`degraded`) → refactor (if any) → caller-count handling (n/a / defer / refactor-in-place / extend-scope / flip-to-hold). Cross-references the per-file entries.
- **Per-file Phase D plan summary table** (file → `migrate` or `hold` → `lib-swap` → rationale) — feeds `coverage.md`'s Phase D plan column and the `phase-d-followups.md` deferred-baseline list.
- **SUT test-classpath gaps** (aggregated) — deps that need `testImplementation` added at Phase B's B.0 source-set bootstrap. Surfaced here so B.0 preempts compile blockers.
- **HTTP client parity tables** (only if an HTTP-client substitution is locked):
  - **Per-service timeout parity** — `<service-key>: connectTimeoutMillis, requestTimeoutMillis, socketTimeoutMillis` for every service, sourced verbatim from pre-migration code.
  - **Server-registration parity** — each new/changed host with its shared-config-object entry name + build-time constant name(s).
- **Transitive-consumer risk register** (from sub-phase 1) — for each locked substitution, the list of transitive consumers + chosen handling (tolerate / bump-together / defer).
- **Helper/foundation deletion plan** — each deletion action with caller-count and chosen handling (defer / refactor-in-place / extend-scope).
- **Batch dep-direction verification result** — `order verified` or the violation list that triggered a re-order.
- Cross-file synthesis (Phase D migration order for `migrate`-plan files, DI plan, risk register)
- Foundation `expect`/`actual` plan (consolidated interfaces with their ≥2 consumers)
- Self-review notes
- Decisions log

---

## Phase-specific gates

Beyond universals:

- **Context7-first for library/SDK/API specifics, web search for patterns** (per SKILL.md Tooling discipline) before any architectural decision. No training-data assumptions about KMM patterns or library behavior.
- **Platform-ownership decisions (storage / DI-symbol placement / logging / catch-all) all recorded** (sub-phase 1.6) before Phase A completes — Phase D will not start without them.
- **Every locked substitution has a verified-existing, Kotlin-compatible version** (sub-phase 1) — no aspirational versions.
- **Plan validation pass run** (sub-phase 1.7) when the plan is non-trivial, including the "what's new in 12 months" sweep — or an announced skip for a trivial pure-Kotlin move.
- **Every "Android-only / non-portable" dep verdict cites its gradle-metadata check** (sub-phase 3 hard gate) — no inference from the `:app` call site.
- Per-file entries use the enumerated output values only (`Phase D plan`, `lib-swap`, iOS verdict).
- Every classification and seam strategy cites evidence (search finding, dep analysis, profile rule).
- Every in-scope file has a recorded `Phase D plan` (`migrate` / `hold`) with rationale.
- New interfaces meet the ≥2-consumer test or get inlined.
- **No `TODO` / stub / deferred-work in the plan.** *"We'll figure this out in Phase D"* is not allowed — Phase A is where it's figured out. Quality of Phase A directly determines speed of Phase D.
- `Phase D plan: hold` decisions surface to user explicitly with rationale; not silent.
- **Every file with `Phase D plan: migrate` carries an iOS Swift interop assessment** with a verdict (`clean` / `blocked` / `degraded`) and a search-cache citation. `blocked` verdicts carry a must-needed refactor with caller-count evidence and route through the scope-creep options (defer / refactor-in-place / extend-scope / flip-to-hold). No silent migrations into `commonMain` without the iOS surface assessed; Phase F.2 verifies the design, it does not discover it.

## A note on Phase A quality vs Phase D speed

**Phase D's batched compile-fix loop depends on plan.md predetermining the substitutions.** Incomplete planning here → more non-trivial decisions surface during Phase D → more Opus invocations + user discussion → slower migration. Spend the time here; D pays it back.
