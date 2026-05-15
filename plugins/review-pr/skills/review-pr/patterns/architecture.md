# Architecture Patterns

**Layer boundary violations.**
Data layer classes (repositories, data sources) must not reference UI layer classes (ViewModels, Fragments, Activities). Domain layer must not reference data or UI. Flag any import or dependency that crosses these boundaries in the wrong direction.

**Wrong-direction dependency.**
A lower-level module depending on a higher-level module (e.g. a repository depending on a ViewModel) — flag as architectural inversion.

**Network calls in the UI layer.**
Direct API calls from Fragment, Activity, or Composable — flag. Network calls belong in the data layer (repository or data source).

**Business logic in the UI layer.**
Decision-making, data transformation, or state computation done in Fragment/Activity instead of ViewModel or domain layer — flag.

**Repository bypassed.**
ViewModel calling a data source directly instead of going through a repository — flag. The repository is the single entry point to the data layer.
