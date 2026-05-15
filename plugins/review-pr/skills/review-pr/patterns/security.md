# Security Patterns

**No hardcoded secrets or credentials.**
API keys, tokens, passwords, or private URLs hardcoded in source files must be flagged as blockers. These must be in environment variables, encrypted config, or a secrets manager.

**PII must not appear in logs.**
User IDs, names, emails, financial data, or any personally identifiable information in log statements — flag as blocker. Anti-trigger: log calls guarded by `if (BuildConfig.DEBUG)` or inside a debug-only `Timber.DebugTree` subclass are acceptable; flag only log statements reachable in release builds.

**Sensitive data must not be stored in plain SharedPreferences.**
Tokens, session IDs, or personal data stored in unencrypted SharedPreferences — flag. Use encrypted DataStore or Android Keystore.

**Injection risks.**
String concatenation used to build SQL queries, shell commands, or URLs with user-supplied input — flag as blocker.

**Improper auth checks.**
Endpoints or operations that bypass authentication/authorisation logic conditionally (e.g. `if (debug) skipAuth()`) — flag.

**Exported Android components without permission.**
`Activity`, `Service`, or `BroadcastReceiver` with `android:exported="true"` in the manifest but no `android:permission` attribute — flag. Any app can invoke unprotected exported components.

**WebView JavaScript with untrusted content.**
`webView.settings.javaScriptEnabled = true` without restricting the URLs loaded to trusted origins — flag. Combine with `WebViewClient.shouldOverrideUrlLoading()` to validate URLs.

**Cleartext traffic.**
`android:usesCleartextTraffic="true"` in the manifest, or HTTP (not HTTPS) URLs hardcoded in source — flag as blocker.

**Deep-link intent data without validation.**
`intent.data` or `getStringExtra()` from an incoming deep-link used directly in a query, path, or network call without validation — flag as injection risk.
