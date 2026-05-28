# kmm-qa-autopilot — improvement backlog

Captured during the **first real run**: PR #396 "KMM: migrate reports business logic to commonMain" — 2026-05-28.
Status: **documented, NOT yet applied.** A later pass will edit the skill source in this worktree,
bump versions (plugin.json + marketplace.json entry + top-level + README), and open a PR.

Paths below are relative to `plugins/kmm-qa-autopilot/skills/kmm-qa-autopilot/`.
The live run reads from the install cache (`~/.claude/plugins/cache/punchhq-skills/kmm-qa-autopilot/<ver>/...`);
mirror edits there only if re-testing before reinstall.

---

## Confirmed findings (observed this run)

### #0 — Skill must enforce ProductionRelease builds (currently defaults to ProductionDebug) — HIGHEST PRIORITY
**Goals:** confidence, correctness.
**Problem:** `build-and-install.sh` defaults `PARITY_VARIANT=ProductionDebug`. On sniper-v2-android the
ProductionDebug variant is the **canary/dev** build, not the production app users actually run, and —
critically — debug has `minifyEnabled false` so it **skips R8/shrinking**. PR #396 migrates
Gson→kotlinx.serialization; a missing R8 keep-rule can make the **release** build emit wrong/empty
serialized values while the **debug** build is a perfect 🟢. A debug parity pass is a false-confidence
green for exactly this class of migration. (Caught by the user mid-run: "it used debug build and that
launches canary instead of the app.")
**Evidence:** `app/build.gradle` — `debug { minifyEnabled false }`, `release { minifyEnabled true;
shrinkResources true; proguardFiles ... 'proguard-rules.pro' }`. Both buildTypes share
`signingConfigs.release`, so release installs over debug with the same signature (login preserved, no
uninstall) — there is no downside to defaulting to release except build time.
**Proposed change:**
- `build-and-install.sh`: default `PARITY_VARIANT=ProductionRelease` (keep override for debug).
- SKILL.md Phase 0: state that BOTH builds are ProductionRelease (the shipped artifact), and warn that
  ProductionDebug tests the wrong variant and skips R8.
- Verify the local release keystore/signing is available before the run (it is here — the debug build
  proved it, since debug also uses `signingConfigs.release`).
- See [[feedback-parity-release-builds]].

### #1 — Merged-PR baseline is manual, buried, and the default emits a vacuous green
**Goals:** robustness, confidence.
**Problem:** SKILL.md Phase 0 says only `bash scripts/setup-worktrees.sh <pr>`. The merged-PR
handling (`BASELINE_REF=<merge>^1`) exists only as a comment inside `setup-worktrees.sh`. PR #396
is MERGED, so `git diff origin/master...PRhead` is **empty** → following the skill verbatim
compares near-identical trees and reports "🟢 PARITY HOLDS" having tested nothing.
**Evidence:** `gh` shows `state=MERGED`; `git diff origin/master..._prhead` returned empty; we had
to hand-set `BASELINE_REF=d1191c05^1` (merge commit's first parent = pre-migration master).
**Proposed change:**
- SKILL.md Phase 0: before setup, `gh pr view <pr> --json state,mergeCommit`. If `MERGED` →
  set `BASELINE_REF=<mergeCommit>^1` automatically and announce "PR merged; baselining against
  pre-migration master `<sha>`."
- `setup-worktrees.sh`: detect the merged case itself and default the baseline to `<merge>^1`
  when the live-master→PR diff is empty.
- **HARD GATE:** after computing the heatmap diff, if it is empty → STOP with an error
  ("nothing to compare — misconfigured baseline"), never proceed to a flow run. Cheap, high value.
- Fix the mislabeled echo: `setup-worktrees.sh` prints `master worktree @ origin/master (<sha>)`
  even when `BASELINE_REF` overrides it → print the actual ref, or the report's baseline line is wrong.

### #2 — References assume pre-existing segmented flows that don't exist
**Goal:** robustness (sets correct expectations for the orchestrator).
**Problem:** `references/maestro-parity.md` and SKILL.md lead with "reuse first" and cite concrete
flows `kill_switch/01..06`, `order_modify_cancel/01..07` as if present. This repo's `maestro/` dir
has exactly **one** file (`bundle_size_stress.yaml`); no report/journey flows exist. An orchestrator
trusting "reuse first" wastes time looking, and the examples imply a structure that isn't there.
**Evidence:** `find $MASTER_WT/maestro -name '*.yaml'` → 1 result.
**Proposed change:** reframe as "**generating a flow per journey is the norm**; reuse only if a
matching `maestro/<journey>/` exists." Replace the phantom example names with a note that segmented
flows are a *convention to produce*, not an assumption.

### #3 — Confidence model over-assumes testTags; data screens have none
**Goal:** confidence.
**Problem:** SKILL.md + `maestro-parity.md` foreground `id:`/testTag as the primary signal and tell
you to "add a testTag to both trees" when one is missing. Real value-table screens (Reports) have
**zero** testTags (verified: 0 across 12 report view files), and tagging every dynamic P&L/ledger
cell is impractical. The comparator's **text-multiset** path is the actual oracle for these
screens — the visible amounts/dates ARE the migrated logic's output — and is already implemented in
`compare-parity.py`, but the guidance buries it.
**Evidence:** `grep -rn testTag view/reports/` → 0; `testTagsAsResourceId=true` set globally in
MainActivity, so the mechanism works, the screens just don't use it.
**Proposed change:** in `parity-comparison.md` and SKILL.md, add explicit guidance: "**For value-table
screens (reports, ledgers, statements) the text-multiset comparison is the primary signal; do not
attempt to tag every cell.** Add at most a screen-level `testTag("screen_<name>")` to both trees for
navigation/scoping." Note that historical/static report data makes the text comparison strict (a
strength), and that scroll-boundary text-count deltas are soft hints, not 🔴.

### #4 — Sanctioned divergences in `.kmm/exceptions/*.md` are ignored → correct migration gets a 🔴
**Goal:** confidence (highest-impact item).
**Problem:** the comparator treats **any** confirmed stable-value difference as 🔴 "DIVERGENCE FOUND,"
and SKILL.md says "don't average it away." But this team's KMM migration workflow deliberately bundles
sanctioned behavior changes, documented in `.kmm/exceptions/<date>-<slug>.md`. PR #396 ships
`2026-05-19-week-year-fix.md`: pre-migration the P&L/report date label for 29–31 Dec prints the
ISO week-year (`30/12/2025`); post-migration it prints the calendar year (`30/12/2024`). A naive run
that happens to use a late-Dec range would flag a 🔴 against a documented, intended fix — destroying
trust in the verdict.
**Evidence:** `.kmm/exceptions/2026-05-19-week-year-fix.md` present in the PR tree; describes an
intentional display-only date change, signed off by the project owner.
**Proposed change (REVISED per owner — independent + evidence-backed; do NOT trust the exception docs by default):**
The `.kmm/exceptions/*.md` files are **authors' claims, not ground truth.** The tool must reach its
own verdict from its own evidence; an exception doc never silently turns a 🔴 into a green.
- New Phase-2 step: read `.kmm/exceptions/*.md` for **context only**; list each claimed intentional
  change (field/screen, claimed old→new, window) + whether it's UI-reachable for the test account.
- Always detect/report divergences from the tool's OWN evidence (both values + screenshots).
- When a confirmed divergence **matches** a documented exception, report it as a divergence labeled
  "author-documented as intentional in `<file>` — VERIFY INDEPENDENTLY," and only annotate it as
  expected if the tool's own captured values corroborate the documented old→new exactly. A difference
  the tool cannot independently corroborate **stays 🔴**, doc or no doc.
- No 🔵 "sanctioned = pass" rubber-stamp, no guesswork: the overall verdict is evidence-based. See
  [[qa-independent-evidence]].
- **Reachability caveat (observed PR #396):** the week-year divergence was documented but **not
  UI-observable** this run — every report uses FY chips (FY22-23…FY26-27), no arbitrary calendar
  picker, and FY boundaries (Apr 1 / Mar 31) never fall in the 29–31 Dec week-year window. It only
  surfaces in (a) the emailed report's **filename** (not on screen) or (b) a **transaction row dated
  29–31 Dec** (data-dependent; this account had none in P/L/Ledger/TradeBook). So when Phase 2 reads
  an exception it should also state **whether it's reachable through the UI for the test account** —
  an unreachable documented divergence is a named gap, not a validated 🔵.

### #9 — Stateful/server actions on a SHARED account across A+B give order-dependent responses → false 🔴
**Goal:** confidence, robustness.
**Problem:** both devices log into the **same prod account**, and the run issues each action on A then B.
For a **stateful** action (email/download/submit/send), the backend responds based on request history,
so the **second** identical request sees mutated server state and returns different copy — a false 🔴
unrelated to the build.
**Evidence (PR #396, Contract Notes "EMAIL THE REPORT"):** A-first showed *"You will receive the
requested report…"*; B-second showed *"We have sent this report…"* → 🔴. Swapping order (B-first,
A-second) made **both** show *"We have sent…"*. The first-ever request gets one message, all later
ones another. The text isn't in either build's source (server-driven); the only hardcoded string
(`ReportDownloadedBS.kt` default) is byte-identical across builds. Pure account/server state.
**Proposed change:**
- In Phase 2/3, mark "submit/send/download/email" checkpoints **stateful**; for these compare the
  **pre-submit state + that the action fired**, NOT the post-submit server confirmation copy.
- Treat a stateful-action confirmation diff like **EVICTION**: a known non-parity condition (run the
  action on one device only, or accept first-vs-repeat asymmetry) rather than a 🔴.
- Comparator: allow `--server-state-text <pattern>` to mask backend-driven confirmation copy.

### #10 — Add Phase 8: auto session-retro → `retro.md` (the skill self-improves every real run)
**Goal:** the meta-goal — make the skill better after every real run (speed/robustness/confidence/harness).
**Problem:** the skill ends at the report + cleanup. All the friction a real run exposes — slow phases,
false 🔴s and their root cause, manual workarounds/deviations, ambiguous or unreachable cases, missing
automation — evaporates unless a human notes it by hand. That hand-capture is exactly what we did this
session into this `improvements.md`; it should be a built-in phase, not a one-off.
**Proposed change:**
- New **Phase 8 — Session retro** (after the report; runs even though Phase 7 cleaned up): produce a
  structured retrospective of THIS run and write **`$RUN_DIR/retro.md`**.
- During the whole run, observe and collect (don't fix): what hurt **speed** (phase timings, slow
  steps), **robustness** (failures, manual re-syncs, deviations like a non-Maestro probe), **confidence**
  (false 🔴s + proven root cause, masked/over-strict cases, unreachable documented changes), **harness**
  (anything the operator had to hand-drive). Then write each as: observation → **evidence from this run**
  → proposed skill change → goal — same shape as this file.
- **Save only. No skill edits during the run.** End by telling the user the retro is at
  `$RUN_DIR/retro.md` and can be triaged into the skill **in a separate session** (edit source in a
  worktree, bump versions, PR).
- Keep it evidence-backed, no guesswork — see [[qa-independent-evidence]]. (This is the productized,
  every-run version of what produced `improvements.md` today.)

---

## Carried-over watch-list (to validate against more runs before applying)

### #5 — A/B run sequentially at runtime (Maestro + capture)
**Goal:** speed. Phase 4/5 runs `maestro --device A` then `--device B`, then 4 sequential captures.
The two devices are independent; running A and B **concurrently** (parallel maestro + parallel
capture) could roughly halve wall-clock per checkpoint. Risk: interleaved logs, host load. Validate
the time saved on a multi-checkpoint journey before committing. NOTE: does **not** apply to builds —
see Learned, below.

### #6 — No journey-loop script (harness gap, likely biggest lever)
**Goal:** speed, robustness, reproducibility. Phase 4/5 is a hand-driven for-loop: the orchestrator
issues every `maestro test` + 4 `capture-checkpoint` + `compare-parity` by hand, per checkpoint. A
`run-journey.sh <journey-dir> <A> <B> <RUN_DIR>` that runs the segments in lockstep, captures, compares,
and writes a journey verdict would cut LLM round-trips, remove transcription errors, and make runs
reproducible/resumable. The `for seg in ...` loop already sketched in `maestro-parity.md` is the seed.

### #7 — No step/scroll-offset guard → spurious 🔴 (CONFIRMED this run)
**Goal:** robustness/confidence. A flaky tap or a scroll that lands at a slightly different offset
leaves one device showing an extra boundary row, producing false presence divergences.
**Evidence (PR #396, Ledger scroll):** a mid-scroll checkpoint flagged 🔴 — A showed one extra row
(`13/04/26 | 00:00 / BILL ENTRY FOR M-2026067`) that B didn't. Scrolling **both to the bottom**
(where offsets converge) re-compared to 🟢 with zero A-only/B-only. Pure scroll-offset drift, not a
migration bug — but the raw run reported 🔴.
**Proposed change:** for scroll/paging checkpoints, don't compare arbitrary mid-scroll offsets —
scroll to a **deterministic anchor** (list bottom, or `scrollUntilVisible` a known end marker) before
capturing; and on a presence-only diff at a list boundary, auto-converge (scroll the lagging device
one step / both to bottom) and re-compare before recording a 🔴. Also assert both devices show the
expected screen marker before capture. `parity-comparison.md` mentions confirming desync manually —
make it automated.

### #8 — No coverage/confidence signal in the report
**Goal:** confidence. A 🟢 on a shallow flow is a false green. Add a per-journey confidence indicator
to the report: which interactions were actually exercised (date-range/scroll/expand/submit), tagged-vs-
text signal strength, and how many fields were masked. Makes "🟢 PARITY HOLDS" auditable.

---

## Learned / refuted (record so we don't re-propose)

- **Do NOT parallelize the two builds.** Observed: master cold ProductionDebug build = **3m17s**; the
  second build reuses the shared Gradle cache and is much faster. Two cold parallel builds would
  contend for CPU/disk and lose the cache-reuse benefit. Sequential build-then-build is already
  near-optimal. (This refutes an early speed hypothesis.)
