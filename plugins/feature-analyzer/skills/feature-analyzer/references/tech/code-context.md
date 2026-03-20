# Code Context

Analyze which parts of the codebase are affected by the feature. Map the change to architecture layers, modules, and files.

## Clean Architecture layer mapping

For each change, identify which layers are touched:

### Presentation layer
- **UI (Compose)**: New screens, modified composables, new UI states
- **ViewModel**: New ViewModels, modified state management, new UI events
- **Navigation**: New routes, modified nav graph, deep link changes
- **Mapper**: Presentation model mapping changes

### Domain layer
- **Use cases**: New use cases, modified business logic
- **Repository interfaces**: New contracts, modified signatures
- **Domain models**: New entities, modified data classes
- **Domain exceptions**: New error types

### Data layer
- **Repository implementations**: New data sources, modified logic
- **Remote data source**: New API calls, modified request/response
- **Local data source**: New Room entities, modified DAOs, new queries
- **Mappers**: DTO to entity mapping changes
- **Data models**: New DTOs, modified API contracts

### DI (Hilt)
- **New modules**: New Hilt modules needed
- **Modified modules**: Existing bindings that change
- **Scope changes**: Singleton vs Activity vs ViewModel scoped

## Analysis questions

For each affected area, answer:
- Is this a new file or modification to existing?
- If modification — what's the blast radius of the change?
- Does this change a shared model used by multiple features?
- Does this introduce a new dependency between modules?
- Is there existing code that can be reused or extended?

## Output format

```
### Code context
**New files needed:**
- [ ] `[layer]/[package]/[FileName.kt]` — [Purpose]

**Existing files modified:**
- [ ] `[layer]/[package]/[FileName.kt]` — [What changes and why]

**Shared models affected:**
- [ ] `[ModelName]` — Used by: [list of features using this model]

**New dependencies introduced:**
- [ ] `[Module A]` → `[Module B]` — [Why this dependency is needed]
```
