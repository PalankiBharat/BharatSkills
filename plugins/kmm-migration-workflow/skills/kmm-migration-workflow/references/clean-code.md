# Clean Code — Migration-Specific Reference

This is a short, opinionated lens for reading source code at architect-time. It is referenced by `references/phases/architect.md` and by `agents/architecture-reviewer.md`. The full clean-code skill (loaded via `clean-code:clean-code`) covers more ground; this file is the migration-relevant subset, with citations the architecture entries point back to.

The point of this lens is not to be exhaustive — it's to give the architect a vocabulary for *why* a piece of source code is a refactor candidate, so that every refactor entry in `architecture.md` cites a concrete, reviewable violation rather than "it would be nicer this way".

## Naming

### §naming.intent-over-mechanism

Names should describe **why** the code exists, not **how** it's implemented. Mechanism-led names (`*Manager`, `*Helper`, `*Holder`, `*Service`, `*Util`, `*Impl`, `process`, `handle`, `execute`) carry no domain meaning — they tell a reader that a thing exists, not what role it plays.

A migration is the cheapest moment to retire mechanism-led names because the file is being rewritten and consumers are being updated anyway.

**Refactor justified when:** a class or function name is mechanism-led AND a clearer domain name exists. Examples:

- `UserManagerImpl` → `UserDirectory` (domain: a thing that holds and looks up users).
- `AuthSdkHolder` → `AuthSession` (domain: an active authentication session).
- `processData(data)` → `parseTransaction(raw)` (domain: parsing a transaction record).

**Refactor NOT justified when:** the mechanism name is widely-recognised in the project's domain (e.g., `LoginViewModel` in an Android codebase that uniformly uses `*ViewModel`), or when the rename would break public API without architecture-approved scope.

### §naming.domain-over-generic

Names should come from the **problem's vocabulary**, not generic programming terms. `data`, `info`, `result`, `value`, `item`, `obj` are signals that the domain hasn't been articulated.

**Refactor justified when:** a parameter/variable/member name is generic AND the domain has a concrete word for it. Example: a method parameter named `data` that always holds a transaction record → rename to `transaction`.

### §naming.function-says-what-it-does

A function's name should describe its **observable effect**, exhaustively. If a reader has to read the body to know what `process()` does, the name is wrong.

**Refactor justified when:** the function name omits a major effect (e.g., `parseInput` that *also* writes to a cache → rename to `parseInputAndCache`, or split — see §functions.one-thing).

## Functions

### §functions.one-thing

A function should do **one thing**. The "one thing" is defined at the function's abstraction level: a high-level function may do "fetch user, validate session, log event", but each of those is itself a single call to a lower-level function that does one thing at *its* level.

**Refactor justified when:** a function does multiple unrelated things at the *same* abstraction level. Example: `processRequest()` that parses, validates, logs, and emits — each is its own concern; extract.

The behaviour-preservation invariant for an extract refactor is: for any input that produces output O in the original function, the new (parse → validate → log → emit) call chain produces the same O.

### §functions.single-abstraction-level

Within a single function, all statements should sit at the same abstraction level. Mixing `cache.get(key)` (low-level) with `processBusinessRule(record)` (high-level) in the same function body is a smell.

**Refactor justified when:** a function mixes abstraction levels AND extracting the lower level into a named helper produces a body that reads as a story at the higher level.

### §functions.no-flag-arguments

Boolean flag arguments often signal that the function does two things — one for `flag=true`, one for `flag=false`. Splitting into two named functions clarifies intent.

**Refactor justified when:** a flag argument toggles between two materially different code paths. Example: `loadUser(fromCache: Boolean)` → `loadUserFromCache()` and `loadUserFromNetwork()`.

## Structure

### §structure.no-scaffolding-without-behaviour

A class or wrapper that **adds no behaviour** is scaffolding. The classic case is the `Holder` pattern: a class whose only job is to hold one or two fields and pass them through. If the holder doesn't enforce an invariant, doesn't expose a domain operation, doesn't gate access — it's structural noise.

**This is the principle the prior incident violated.** Migrating an SDK and introducing `AuthSdkHolder`, `SessionTokenHolder`, `RetryConfigHolder` (none of which add behaviour) does not move the codebase forward; it just moves bad code to a new location.

**Refactor justified when:** a holder/wrapper exists in the source AND removing it (inlining its fields directly into the consumer, or replacing it with the bare type) leaves consumers no worse off. Public API of consumers must stay unchanged.

**Refactor NOT justified when:** the holder *does* enforce an invariant (e.g., `Email` wrapping `String` to guarantee format) or *does* gate access (e.g., `Lazy<T>` for deferred initialisation).

### §structure.no-incidental-complexity

Incidental complexity is shape that exists because the original author worked around something — a tooling limitation, a deprecated API, a temporary platform constraint — that no longer applies. KMM migrations frequently encounter this: code structured around `LiveData` lifecycle assumptions that won't apply once the file moves to commonMain.

**Refactor justified when:** a structural choice in the source is shaped by a constraint the migration removes, AND the simpler shape is straightforwardly behaviour-preserving.

### §structure.no-dead-code

Dead branches, unreachable methods, and unused parameters are noise. They survive because removing them feels risky; the migration is the safe moment to remove them because baseline tests will catch any reachable use.

**Refactor justified when:** a branch is unreachable in any baseline test AND a manual read confirms no path reaches it. (If a branch is uncovered by tests but is *theoretically* reachable, it's a test gap, not dead code — capture a baseline test for it instead.)

## Comments

### §comments.no-comments-by-default

Per Constitution §9, comments default to none. A comment that paraphrases the next line of code is noise. A comment that explains a *why* the code itself can't communicate is useful, but rare.

**Refactor justified when:** the source has a comment that paraphrases code (e.g., `// increment counter` above `counter++`). Drop the comment as part of the migrate-time refactor.

**Refactor NOT justified when:** the comment captures a hidden constraint or non-obvious why (e.g., `// this loop must run in reverse to preserve insertion order on Map.Entry iteration`). Preserve.

## How to use this reference

When the architect phase is reading a file, walk these sections in order. For each finding, capture: `file:line`, the section reference (`§naming.intent-over-mechanism`), a one-line observation. The architecture entry then either turns the finding into a `Refactor` entry (with target shape + behaviour invariant + risk) or notes it as out-of-reach.

A finding without a citation to one of these sections is not a refactor justification. Aesthetic preferences (e.g., "I'd write this as a sealed class") are not in scope. The bar is concrete, named violations of clean-code principles — nothing softer.
