# Phase 5 — iOS wiring (Punch)

Goal: Punch builds with the migrated feature wired end-to-end — shared logic consumed via the `shared` pod, feature screens delivering every contract behavior.

1. **Gate zero (already green from phase 4):** `:shared:compileKotlinIosArm64` + SKIE; the full framework link was proven by phase-4's exit app build (standalone `linkPod*`/XCFramework is not a gate — knowledge base → Gradle gotchas for why).
2. **Discover, don't assume.** kmm-ios-engineer reads what exists plus the knowledge base's "iOS UI strategy" + "iOS app (Punch)" sections — the profile is the single source for the UI strategy and the composition-root traps; this playbook points, it does not restate. Where neither the app nor the knowledge base answers a decision, that's a research question (kmm-researcher: SKIE/CMP consumption of the exact shared types involved — sourced, current) and, if it shapes UX architecture durably, a G3 consult.
3. **Wiring order (TDD throughout):**
   - Phase-4's exit smoke (`pod install` + `xcodebuild build`) is the green starting line; the shared surface is frozen here — re-run `pod install` only if a change forces a return to phase 3/4.
   - Logic binding first. A worker `blocked` report citing "needs Swift-side logic" routes back to phase 3/4 — that routing is the parity guarantee; enforcing no-logic-in-Swift is the agent's job.
4. **Per-screen gate:** `xcodebuild build` green; XCTests green; screen launched on the iOS simulator and exercised against the contract lines it implements (evidence: screenshot per state).
5. **Commit style** as phase 4. Journal everything (Rule 10).

Exit: workspace builds clean, XCTests green, every contract behavior reachable on simulator, journal current. Set phase 6.
