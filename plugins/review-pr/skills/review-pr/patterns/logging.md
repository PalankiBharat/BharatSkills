# Logging Patterns

**Logging calls should be consistent within a class.**
Mixed use of tagged vs. untagged loggers in the same class makes log filtering unreliable. If the class uses `Timber.tag(TAG).d(...)`, every call in that class should use the same form.

**No PII in logs.**
User identifiers, account numbers, tokens, passwords, or personal data must not be logged. Flag any log call that includes user-sourced data without explicit sanitisation.

**Correct log level.**
`d` for debug/tracing, `w` for recoverable unexpected states, `e` for errors that affect functionality. Flag `e` used for informational messages or `d` used for production error paths.

**No logging in tight loops.**
A log statement inside a loop that runs per-frame, per-item, or per-event will flood the log and affect performance. Flag it.
