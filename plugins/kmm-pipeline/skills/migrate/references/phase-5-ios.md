# Phase 5 — iOS wiring (Punch)

Goal: Punch builds with the migrated feature wired end-to-end — shared logic consumed via the `shared` pod, native screens delivering every contract behavior.

1. **Gate zero (already green from phase 4):** `:shared:compileKotlinIosArm64` + SKIE. Do NOT use standalone `linkPod*` or XCFramework links as a gate — the native Finance.framework comes from CocoaPods, not gradle (profile → Gradle gotchas). The full link is proven via the app build below.
2. **Discover, don't assume.** kmm-ios-engineer first reads what exists: `Punch/Punch/PunchApp.swift`, `Screens/`, project structure, how `shared` is already imported, any established navigation/DI/theming idiom. The FIRST migrated screens set precedent — when `Punch/` offers no precedent for a decision (navigation pattern, state binding idiom), that's a research question (kmm-researcher: SKIE consumption of the exact shared types involved — Flows, suspend functions, sealed classes — sourced, current) and, if it shapes UX architecture durably, a G3 consult.
3. **Wiring order (TDD throughout):**
   - `pod install` in `Punch/` so the pod picks up the new shared surface; `xcodebuild build` for the workspace must pass before UI work starts.
   - Logic binding first: Swift code consumes shared ViewModels/UseCases via SKIE wrappers. **No business logic in Swift** — if a behavior needs Swift-side logic beyond view binding/formatting idioms, the logic belongs in commonMain; STOP and route back to phase 3/4 (this is the parity guarantee).
   - XCTest unit tests for the binding layer (red-first) where Swift adds any mapping at all.
   - Screens per contract's iOS deliverable, matching `Punch/` idiom. Every interactive element gets an `accessibilityIdentifier` mirroring the Android `testTag` string for the same element — this is what lets one Maestro flow drive both platforms in QA.
4. **Per-screen gate:** `xcodebuild build` green; XCTests green; screen launched on the iOS simulator and exercised against the contract lines it implements (evidence: screenshot per state).
5. **Commit style** as phase 4. Journal everything (Rule 10).

Exit: workspace builds clean, XCTests green, every contract behavior reachable on simulator, journal current. Set phase 6.
