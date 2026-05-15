# Scalability Patterns

**Missing pagination.**
A query or API call that loads all items without limit or offset — flag when the dataset can grow unboundedly (user lists, transaction history, etc.).

**No caching for repeated remote calls.**
If the same data is fetched from the network on every screen entry with no local cache, flag it — suggest a repository-level cache or Room as the source of truth.

**O(n) operation where O(1) is available.**
`list.contains(item)` in a loop, repeated `indexOf`, or linear scans on growing collections — flag and suggest `Set`/`Map`.

**No debounce/throttle on high-frequency triggers.**
API calls triggered per keystroke, per scroll event, or per sensor update without debounce — flag. Use `debounce` on the Flow or `throttleFirst`.

**Single source of truth violations.**
The same data stored in multiple places (ViewModel + repository + local cache) with no clear ownership or sync strategy — flag. One owner, all others observe.
