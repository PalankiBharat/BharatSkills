# Readability Patterns

**Functions should describe what they act on, not just what they do.**
`process()`, `handle()`, `doStuff()` convey nothing — the name omits what is being acted on. Names should read as verb phrases that include the subject: `recordPillInFirestore()`, `parseSnapshotOrEmpty()`, `isTransientNetworkFailure()`.
Anti-trigger: Lifecycle hooks (`onCreate`, `onPause`, `onViewCreated`), interface overrides, and standard operator names are exempt.

**One level of abstraction per function.**
A function that mixes high-level orchestration with low-level implementation detail is hard to read. Flag functions where some lines read as "what to do" and others as "how to do it at a low level" — split into named micro-functions.

**Inline transformation chains should be named.**
A chain of 3+ operations, or a 2-step chain inside a conditional/function argument where the intent isn't obvious, hides intent. Extract to a named function.

> Signal: `.map { }.toSet()` inside an `if` condition, function parameter, or `remember { }` block — ask "does this chain deserve a name?"
> Anti-trigger: Don't flag two-step transforms inside `let`/`also`/`return` statements where the meaning is clear from surrounding context.
> Example: `fxPlotState.plottedIndicators.map { it.templateId }.toSet()` → `fxPlotState.plottedTemplateIds()`

**Mutable accumulator + loop → pipeline.**
A mutable list + state-mutating `repeat`/`for` loop building a result should be replaced with `generateSequence`, `map`, `fold`, or `buildList` so the data flow reads top-to-bottom.
