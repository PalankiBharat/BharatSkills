# Dependency Version Patterns

**Feature-branch / pre-release SDK versions must not ship to production.**
Any version with a suffix like `-001-feature-name`, `-alpha`, `-SNAPSHOT`, `-dev`, `-rc` is a development artifact. Before merge, it must be replaced with the stable release version.

> Signal: `dependency_version = 'x.y.z-anything'` in `build.gradle` / `libs.versions.toml`
> Fix: bump to `'x.y.z'` (the stable published release) before merging to master.
