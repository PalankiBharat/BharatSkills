> Per-type reference. Cross-cutting rules, Toolbox, decision matrices, file-level skeletons, and Verification gates live in `index.md`. Load both. **Hand-rolled fakes only** — MockK is banned in baseline source sets (`<dest>/androidUnitTest`, `<dest>/commonTest`); see `index.md` Toolbox and "Fakes vs mocks — when?".

# 9. Presenters

> Path: `app/src/main/java/.../presenter/**`
> Stack: **KMM-portable** by default — same rationale as ViewModels.

### Responsibility

Format ViewModel/UseCase output for the UI (button labels, colors,
visible/gone states). Stateless or near-stateless; expose
`StateFlow<UiModel>` to be collected by a Composable.

### What to mock

- ✅ Anything the presenter pulls from (use cases, repositories) — hand-rolled fakes. No MockK (banned in baseline source sets — see `index.md` Toolbox).
- ✅ Resource provider (`IStringResourceRepository`) — define as an interface, fake in tests.
- ❌ Don't mock the presenter itself.

### Coverage checklist

- [ ] Each state branch produces the expected display values (button text, color, icon, visibility).
- [ ] Localisation: use a fake `IStringResourceRepository` that returns string-resource **keys** instead of strings — assert on the key, not the localized output.
- [ ] Number formatting honors `Locale.US` for decimal points (or, in `commonMain`, use `kotlin.text` formatting helpers that don't depend on JVM `Locale`).
- [ ] When upstream emits the same value twice, presenter conflates and emits once (or N times — assert whichever the contract is, document it in the test name).

### Template

Same skeleton as ViewModels (kotlin.test + hand-rolled fakes + Turbine — see `index.md` File-level skeleton);
substitute `Presenter` for `ViewModel`.

### Anti-patterns

- Asserting on String content. Use string-resource *keys*; they don't break on translation updates.
- Coupling the test to `R.string.foo` ID values — use a fake resource provider, never `R.*` directly (also: `R.*` is androidx-only and won't move to `:shared`).

---

