# Design Patterns & Anti-Patterns

**Law of Demeter — a caller should not navigate a model's internal structure.**
`a.b[i].c.d` is a train wreck — the caller knows too much about how `a` is built. If internal representation changes, every caller breaks. The model should expose what callers need directly.

> Signal: chained member accesses (`fxMenu.fxTypes[index].kind`) — any chain longer than one hop into a data structure.
> Fix: add a method on the owning type (`fxMenu.kindAt(index)`) so the caller asks for what it needs.
> Rule of thumb: "one dot" for your own object's fields is fine; "two dots into someone else's object" is a smell.

> **Map/collection field access** — `entity.someMap[key]` exposes that the entity uses a Map internally and is keyed by that key type. Flag when: the map field is accessed outside the entity class using a key derived from another object (`entity.pills[category.key]`, `entity.data[user.id]`). Fix: add a named accessor on the entity (`entity.pillsFor(category)`, `entity.dataFor(user)`).

**The fix for a train wreck must not create a new one one level up.**
Extracting `list.map { it.id }.toSet()` as `state.list.extractedIds()` just moves the chain — the caller still reaches into `state` to get its list. The method belongs on `state` itself: `state.extractedIds()`.

**Inline transformation chains should be named.**
When a chain of operations (`.map { }.toSet()`, `.filter { }.first()`) appears inside a condition or a function argument — it hides intent. Extract it as a named function.

> `fxPlotState.plottedIndicators.map { it.templateId }.toSet()` → `fxPlotState.plottedTemplateIds()`

**Flag missed Strategy pattern opportunities.**
Chained `when`/`if-else` that switches on the same type or enum in 3+ places, or where each branch does substantively different work (not just sets a field), is a Strategy pattern waiting to emerge. Do NOT flag simple 2-branch `when` expressions.

**Flag God Object anti-pattern.**
A class that spans 3+ unrelated concerns, or exceeds ~200 lines of substantive logic, or owns fields from multiple bounded contexts — flag and suggest splitting by responsibility.
