# KMM Runtime-Golden Parity Loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the `kmm-migration` skill so its final phase is a closed, autonomous `/loop` that verifies the migrated build against a runtime behavioral golden (captured early via agent-device), fixing parity-restoring bugs through the existing workflow until a user-readable QA checklist is all-green.

**Architecture:** A new *user/QA-lens journey catalog* (Phase 0/A) drives a *runtime golden* capture on master (Phase B, agent-device records real network wires + computed UI outputs, gitignored, PII-gated, frozen). Phase F renders the catalog as the heatmap and upgrades the smoke/HTTP/crash checks to agent-device. Phase I is rewritten as a `/loop` that **replays the frozen golden to the migrated build** (deterministic, exact-diff — correct for a trading app) and falls back to live A/B with narrow masking only for un-recordable streaming surfaces. Two new shippable scripts (PII gate, golden compare) plus a thin agent-device capture wrapper. A research spike (R1–R4) resolves the replay-harness mechanism before the harness-dependent content is finalized.

**Tech Stack:** Markdown skill authoring; `bash` + `python3` (stdlib only — no pip deps) for scripts; `agent-device` CLI (Node 22+); `claude plugin validate .` as the structural test; the repo's four-place version-bump rule.

**Spec:** `docs/superpowers/specs/2026-06-05-kmm-runtime-golden-parity-loop-design.md`

**Working tree:** worktree `../claude-code-skills-parity-loop`, branch `feat/kmm-runtime-golden-parity-loop` (already created; the spec is already committed here).

---

## Conventions for this plan

This is a **skill-authoring repo**, not an app — there is no build/lint/unit-test runner for the markdown. The verification analogs are:

- **Structural test (every markdown task):** `claude plugin validate .` must pass.
- **Consistency test (every markdown task):** a targeted `grep` proving the edit's load-bearing anchors/cross-references exist and resolve (given per task).
- **Real tests (script tasks):** `python3 tests/<name>.py` (plain `assert` + `__main__` runner; stdlib only) and a `bash tests/<name>.sh` exit-code/grep check. No pytest dependency.

**Commit discipline:** one commit per task (the task's "Commit" step). Conventional messages, `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Do **not** bump versions until Task 8.x (single lockstep bump at the end).

**Normalized capture format (used by the scripts so they're testable independent of agent-device's exact output):** a checkpoint is a JSON file:

```json
{
  "journey": "holdings-pnl",
  "checkpoint": "after-date-range-change",
  "anchor": "txt_total_pnl",
  "elements": [
    {"ref": "txt_total_pnl", "role": "text", "text": "₹1,200.50", "computed": true, "live": false},
    {"ref": "ticker_nifty", "role": "text", "text": "22,140.05", "computed": false, "live": true}
  ],
  "network": [
    {"method": "GET", "url": "https://…/holdings", "status": 200, "body_sha256": "…", "body_path": "wires/holdings.json"}
  ]
}
```

`computed: true` = a value the migrated logic produces (P&L, totals, derived prices) → **never masked**. `live: true` = an externally-fed feed not derived from migrated logic (raw tick, chart axis) → maskable. `ad-capture.sh` (Task 1.4) is the adapter that produces this format from real agent-device output; the exact field mapping is finalized in the M0 spike (R1).

---

## Milestone 0 — Research spike (R1–R4) — GATES harness-dependent work

Resolves the one genuinely unverified dependency (the replay harness) and agent-device's real output shape, then records the decisions. **Tasks 4.x (golden capture replay note) and 7.x (Phase I replay path) must not be finalized until this milestone's decision artifact exists.** Catalog/heatmap/script-foundation work (M1–M4 below, except the replay note) does NOT depend on this and can proceed in parallel.

### Task 0.1: Stand up agent-device and capture its real output shapes

**Files:**
- Create: `docs/superpowers/research/2026-06-05-agent-device-spike.md`

- [ ] **Step 1: Install and smoke agent-device**

Run:
```bash
npm install -g agent-device@latest
agent-device --version
agent-device help workflow > /tmp/ad-workflow-help.txt
agent-device help snapshot > /tmp/ad-snapshot-help.txt 2>&1 || true
agent-device help network > /tmp/ad-network-help.txt 2>&1 || true
agent-device help replay > /tmp/ad-replay-help.txt 2>&1 || true
agent-device help record > /tmp/ad-record-help.txt 2>&1 || true
```
Expected: a version prints; the help topics dump to the temp files.

- [ ] **Step 2: Capture a real snapshot + network sample against any installed app**

Run (against an emulator/sim with any app, e.g. the sniper ProductionDebug if available):
```bash
agent-device apps --platform android
agent-device open <AnyApp> --platform android
agent-device snapshot -i | tee /tmp/ad-snapshot.txt
agent-device network --help 2>&1 | tee -a /tmp/ad-network-help.txt
agent-device close
```
Expected: a snapshot listing with `@eN [role] "text"` refs; note the **exact** text/role format and whether a machine-readable (JSON) snapshot flag exists.

- [ ] **Step 3: Record the findings (R1–R4) into the spike doc**

Write `docs/superpowers/research/2026-06-05-agent-device-spike.md` answering, with evidence quoted from the temp files:
- **R1 — Replay capability:** Can agent-device *serve/replay* recorded network responses as a mock, or only capture? Quote the `help network`/`help replay` output. **Decision:** `agent-device-native-replay` | `external-proxy-needed` | `app-side-interceptor`.
- **R2 — App base-URL config:** In `sniper-v2-android`, can the HTTP base URL be pointed at a local mock per flavor? Inspect `project.md` networking fields and the BuildKonfig host constants (`networking.shared_client_config.host_constant_convention`). Record the exact constant names + which variant is mockable.
- **R3 — Frozen-input determinism:** Identify which inputs the migrated computed outputs depend on beyond the response body (server timestamps, sequence numbers, session tokens). Record what must be frozen for replay to reproduce a value to the digit.
- **R4 — iOS surface detection:** Define a deterministic check for "an iOS UI path consumes the migrated code this session" (e.g., the migrated symbols appear in an iOS target's call graph / a Swift screen imports the shared module type). Record the check.
- **Normalized-format mapping:** the exact transform from agent-device snapshot output → the normalized checkpoint JSON (above). This finalizes `ad-capture.sh`.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/research/2026-06-05-agent-device-spike.md
git commit -m "research(kmm): agent-device + replay-harness spike (R1-R4)"
```

### Task 0.2: Select the replay mechanism and record it

**Files:**
- Modify: `docs/superpowers/research/2026-06-05-agent-device-spike.md` (add a "Decision" section)

- [ ] **Step 1: Write the decision**

Append a `## Decision` section choosing the replay mechanism from R1's options, with the concrete wiring for `sniper-v2-android` (the script that seeds/serves recordings, the env var/flavor that points the app at it, and the per-journey fallback to live-A/B when replay is infeasible). If R1 = `agent-device-native-replay`, the mechanism is the `agent-device replay` of captured wires; otherwise specify the proxy/interceptor.

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/research/2026-06-05-agent-device-spike.md
git commit -m "research(kmm): select replay mechanism for the parity loop"
```

> **Gate:** Tasks 4.3 and 7.3 read this decision section. Do not finalize them before it exists.

---

## Milestone 1 — Shippable scripts (new `scripts/` dir)

`SKILL_DIR = plugins/kmm-migration-workflow/skills/kmm-migration`

### Task 1.1: PII/secret gate for the golden — failing test

**Files:**
- Create: `SKILL_DIR/scripts/tests/test_scrub_pii.py`
- Test target (next task): `SKILL_DIR/scripts/scrub-pii.py`

- [ ] **Step 1: Write the failing test**

Create `SKILL_DIR/scripts/tests/test_scrub_pii.py`:
```python
import json, subprocess, sys, os, tempfile

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "scrub-pii.py")

def run(args, expect_code=None):
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)
    if expect_code is not None:
        assert p.returncode == expect_code, f"code {p.returncode}, out={p.stdout} err={p.stderr}"
    return p

def test_detects_pii_classes_in_golden():
    with tempfile.TemporaryDirectory() as d:
        wires = os.path.join(d, "wires.json")
        with open(wires, "w") as f:
            json.dump({"phone": "9876543210", "token": "Bearer eyJhbGciOi.JIUzI1.abc",
                       "pan": "ABCDE1234F", "balance": "12000.50"}, f)
        # --scan reports PII classes found, exit 0 (report-only); names the classes
        p = run(["--scan", wires], expect_code=0)
        for cls in ("phone", "auth_token", "pan"):
            assert cls in p.stdout, f"{cls} not reported: {p.stdout}"
        assert "balance" not in p.stdout  # a financial value is NOT pii

def test_scrub_redacts_for_shareable_artifact():
    with tempfile.TemporaryDirectory() as d:
        art = os.path.join(d, "report.md")
        with open(art, "w") as f:
            f.write("user 9876543210 saw token Bearer eyJhbGciOi.JIUzI1.abc and PAN ABCDE1234F")
        run(["--scrub", art], expect_code=0)
        out = open(art).read()
        assert "9876543210" not in out and "[REDACTED:phone]" in out
        assert "ABCDE1234F" not in out and "[REDACTED:pan]" in out
        assert "eyJhbGciOi" not in out

def test_gate_fails_when_golden_path_not_gitignored():
    # --gate <dir>: exit 2 if the dir is NOT git-ignored (golden must never be committable)
    p = run(["--gate", "/definitely/not/ignored/golden"], expect_code=2)
    assert "not gitignored" in (p.stdout + p.stderr).lower()

if __name__ == "__main__":
    test_detects_pii_classes_in_golden()
    test_scrub_redacts_for_shareable_artifact()
    test_gate_fails_when_golden_path_not_gitignored()
    print("ok")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 SKILL_DIR/scripts/tests/test_scrub_pii.py`
Expected: FAIL — `scrub-pii.py` does not exist (FileNotFoundError / nonzero).

### Task 1.2: PII/secret gate — implementation

**Files:**
- Create: `SKILL_DIR/scripts/scrub-pii.py`

- [ ] **Step 1: Implement**

Create `SKILL_DIR/scripts/scrub-pii.py`:
```python
#!/usr/bin/env python3
"""PII/secret gate for the runtime golden (trading data).

Three modes:
  --scan <file>   Report which PII classes appear (report-only, exit 0). Used to
                  inform the user that the golden contains PII and must stay local.
  --scrub <file>  Redact PII in place for a SHAREABLE artifact (report / PR text).
                  Never run on golden wires — replay needs them intact.
  --gate <dir>    Exit 2 unless <dir> is git-ignored. The golden must never be
                  committable. Exit 0 when ignored.

Financial values (balances, amounts) are NOT PII and are never touched.
"""
import re, sys, subprocess

PATTERNS = {
    "phone":      re.compile(r"\b(?:\+?91[-\s]?)?[6-9]\d{9}\b"),
    "auth_token": re.compile(r"\b(?:Bearer\s+)?eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"),
    "pan":        re.compile(r"\b[A-Z]{5}[0-9]{4}[A-Z]\b"),
    "aadhaar":    re.compile(r"\b\d{4}\s?\d{4}\s?\d{4}\b"),
    "email":      re.compile(r"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b"),
}

def scan(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    found = [name for name, rx in PATTERNS.items() if rx.search(text)]
    if found:
        print("PII classes found: " + ", ".join(found))
    else:
        print("no PII classes found")
    return 0

def scrub(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    for name, rx in PATTERNS.items():
        text = rx.sub(f"[REDACTED:{name}]", text)
    open(path, "w", encoding="utf-8").write(text)
    print(f"scrubbed {path}")
    return 0

def gate(path):
    r = subprocess.run(["git", "check-ignore", "-q", path])
    if r.returncode == 0:
        print(f"ok: {path} is gitignored")
        return 0
    print(f"BLOCKED: {path} is not gitignored — the golden must never be committable", file=sys.stderr)
    return 2

def main(argv):
    if len(argv) != 3 or argv[1] not in ("--scan", "--scrub", "--gate"):
        print(__doc__); return 64
    return {"--scan": scan, "--scrub": scrub, "--gate": gate}[argv[1]](argv[2])

if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 2: Run test to verify it passes**

Run: `python3 SKILL_DIR/scripts/tests/test_scrub_pii.py`
Expected: prints `ok`.
Note: `test_gate_fails_when_golden_path_not_gitignored` runs `git check-ignore` from the repo — the fake path is not ignored, so exit 2. Run from inside the worktree.

- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/scripts/scrub-pii.py SKILL_DIR/scripts/tests/test_scrub_pii.py
git commit -m "feat(kmm): scrub-pii.py — golden PII gate (scan/scrub/gitignore-gate)"
```

### Task 1.3: Golden comparator — failing test

**Files:**
- Create: `SKILL_DIR/scripts/tests/test_compare_golden.py`

- [ ] **Step 1: Write the failing test**

Create `SKILL_DIR/scripts/tests/test_compare_golden.py`:
```python
import json, subprocess, sys, os, tempfile

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "compare-golden.py")

def write(d, name, obj):
    p = os.path.join(d, name)
    with open(p, "w") as f: json.dump(obj, f)
    return p

def run(golden, candidate):
    return subprocess.run([sys.executable, SCRIPT, golden, candidate], capture_output=True, text=True)

def base(total="₹1,200.50"):
    return {"journey": "holdings", "checkpoint": "c1", "anchor": "txt_total",
            "elements": [
                {"ref": "txt_total", "role": "text", "text": total, "computed": True, "live": False},
                {"ref": "ticker", "role": "text", "text": "22,140.05", "computed": False, "live": True},
            ]}

def test_identical_is_parity():
    with tempfile.TemporaryDirectory() as d:
        g = write(d, "g.json", base()); c = write(d, "c.json", base())
        p = run(g, c)
        assert p.returncode == 0 and "PARITY" in p.stdout, p.stdout

def test_computed_value_divergence_is_red():
    with tempfile.TemporaryDirectory() as d:
        g = write(d, "g.json", base("₹1,200.50")); c = write(d, "c.json", base("₹1,020.50"))
        p = run(g, c)
        assert p.returncode == 1 and "DIVERGENCE" in p.stdout, p.stdout
        assert "txt_total" in p.stdout

def test_live_field_difference_is_ignored():
    with tempfile.TemporaryDirectory() as d:
        g = base(); c = base()
        c["elements"][1]["text"] = "22,155.90"  # live ticker moved — must NOT fail
        gp = write(d, "g.json", g); cp = write(d, "c.json", c)
        p = run(gp, cp)
        assert p.returncode == 0 and "PARITY" in p.stdout, p.stdout

def test_anchor_absent_on_candidate_is_indeterminate():
    with tempfile.TemporaryDirectory() as d:
        g = base(); c = base()
        c["elements"] = [e for e in c["elements"] if e["ref"] != "txt_total"]
        gp = write(d, "g.json", g); cp = write(d, "c.json", c)
        p = run(gp, cp)
        assert p.returncode == 3 and "INDETERMINATE" in p.stdout, p.stdout

if __name__ == "__main__":
    test_identical_is_parity()
    test_computed_value_divergence_is_red()
    test_live_field_difference_is_ignored()
    test_anchor_absent_on_candidate_is_indeterminate()
    print("ok")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 SKILL_DIR/scripts/tests/test_compare_golden.py`
Expected: FAIL — `compare-golden.py` does not exist.

### Task 1.4: Golden comparator — implementation

**Files:**
- Create: `SKILL_DIR/scripts/compare-golden.py`

- [ ] **Step 1: Implement**

Create `SKILL_DIR/scripts/compare-golden.py`:
```python
#!/usr/bin/env python3
"""Compare a candidate (migrated) checkpoint against the frozen golden checkpoint.

Trading-app rule: a `computed` element (value the migrated logic produces) must
match EXACTLY and is NEVER masked. A `live` element (externally-fed feed not
derived from migrated logic) is ignored. The checkpoint `anchor` must be present
on BOTH sides or the comparison is vacuous.

Verdicts / exit codes:
  PARITY        0   all computed elements match, anchor present both sides
  DIVERGENCE    1   a computed element differs
  INDETERMINATE 3   anchor absent on golden or candidate (vacuous comparison)
"""
import json, sys

def load(p): return json.load(open(p, encoding="utf-8"))
def by_ref(cp): return {e["ref"]: e for e in cp.get("elements", [])}

def main(argv):
    if len(argv) != 3:
        print("usage: compare-golden.py <golden.json> <candidate.json>"); return 64
    g, c = load(argv[1]), load(argv[2])
    anchor = g.get("anchor")
    gmap, cmap = by_ref(g), by_ref(c)
    if anchor not in gmap or anchor not in cmap:
        side = "golden" if anchor not in gmap else "candidate"
        print(f"⚪ INDETERMINATE — anchor '{anchor}' absent on {side}; comparison vacuous")
        return 3
    diffs = []
    for ref, ge in gmap.items():
        if not ge.get("computed") or ge.get("live"):
            continue  # never compare a live/non-computed field
        ce = cmap.get(ref)
        if ce is None:
            diffs.append(f"{ref}: missing on candidate (golden '{ge['text']}')")
        elif ce.get("text") != ge.get("text"):
            diffs.append(f"{ref}: golden '{ge['text']}' ⇄ candidate '{ce['text']}'")
    if diffs:
        print("🔴 DIVERGENCE — " + "; ".join(diffs))
        return 1
    print("🟢 PARITY — all computed values match (anchor reached on both)")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 2: Run test to verify it passes**

Run: `python3 SKILL_DIR/scripts/tests/test_compare_golden.py`
Expected: prints `ok`.

- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/scripts/compare-golden.py SKILL_DIR/scripts/tests/test_compare_golden.py
git commit -m "feat(kmm): compare-golden.py — computed-value parity (never-mask rule)"
```

### Task 1.5: agent-device capture wrapper (adapter to normalized format)

**Files:**
- Create: `SKILL_DIR/scripts/ad-capture.sh`
- Create: `SKILL_DIR/scripts/tests/test_ad_capture.sh`

> The exact agent-device→normalized mapping is finalized from the M0 spike (Task 0.1 Step 3). This task ships the wrapper skeleton + a test that runs in CI-without-a-device by honoring an `AD_BIN` override pointing at a stub.

- [ ] **Step 1: Write the failing test (with a stub agent-device)**

Create `SKILL_DIR/scripts/tests/test_ad_capture.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
# stub agent-device: emits one interactive element line
cat > "$tmp/ad-stub" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  snapshot) echo '@e1 [text] "₹1,200.50"';;
  *) : ;;
esac
STUB
chmod +x "$tmp/ad-stub"
AD_BIN="$tmp/ad-stub" bash "$here/../ad-capture.sh" --device emu --journey holdings \
  --checkpoint c1 --anchor txt_total --out "$tmp/cp.json"
python3 - "$tmp/cp.json" <<'PY'
import json,sys
cp=json.load(open(sys.argv[1]))
assert cp["journey"]=="holdings" and cp["checkpoint"]=="c1" and cp["anchor"]=="txt_total"
assert isinstance(cp["elements"],list) and len(cp["elements"])>=1
print("ok")
PY
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash SKILL_DIR/scripts/tests/test_ad_capture.sh`
Expected: FAIL — `ad-capture.sh` does not exist.

- [ ] **Step 3: Implement the wrapper**

Create `SKILL_DIR/scripts/ad-capture.sh`:
```bash
#!/usr/bin/env bash
# Drive one journey checkpoint with agent-device and emit a normalized checkpoint JSON.
# Honors AD_BIN (default: agent-device) so tests can inject a stub.
# Real network/log/crash capture flags are wired in per the M0 spike (R1) findings.
set -euo pipefail
AD="${AD_BIN:-agent-device}"
device="" journey="" checkpoint="" anchor="" out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --device) device="$2"; shift 2;;
    --journey) journey="$2"; shift 2;;
    --checkpoint) checkpoint="$2"; shift 2;;
    --anchor) anchor="$2"; shift 2;;
    --out) out="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 64;;
  esac
done
snap="$("$AD" snapshot -i 2>/dev/null || true)"
# Parse '@eN [role] "text"' lines into normalized elements. computed/live default
# to false; the loop (Phase I) tags computed/live from the journey catalog metadata.
python3 - "$journey" "$checkpoint" "$anchor" "$out" <<PY
import json,re,sys
journey,checkpoint,anchor,out=sys.argv[1:5]
snap='''$snap'''
els=[]
for m in re.finditer(r'@(\S+)\s+\[([^\]]+)\]\s+"([^"]*)"', snap):
    ref,role,text=m.groups()
    els.append({"ref":ref if not ref.startswith('e') else (anchor if text else ref),
                "role":role,"text":text,"computed":False,"live":False})
# Ensure the anchor ref exists if its text was captured (stub maps first text elem).
if els and not any(e["ref"]==anchor for e in els):
    els[0]["ref"]=anchor
json.dump({"journey":journey,"checkpoint":checkpoint,"anchor":anchor,
           "elements":els,"network":[]}, open(out,"w"), indent=2)
PY
echo "wrote $out"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash SKILL_DIR/scripts/tests/test_ad_capture.sh`
Expected: prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add SKILL_DIR/scripts/ad-capture.sh SKILL_DIR/scripts/tests/test_ad_capture.sh
git commit -m "feat(kmm): ad-capture.sh — agent-device -> normalized checkpoint adapter"
```

---

## Milestone 2 — New reference docs

### Task 2.1: `references/agent-device.md`

**Files:**
- Create: `SKILL_DIR/references/agent-device.md`

- [ ] **Step 1: Write the reference**

Create `SKILL_DIR/references/agent-device.md` containing exactly these sections:
- **Command surface** — table of the commands the skill uses (`apps`, `open`, `snapshot -i`, `tap`/`fill`/`scroll`, `assert`, `wait`, `screenshot`, `logs`, `network`, crash capture, `record`/`replay`, `close`) with one-line purpose each. Note Node 22+, Xcode (iOS), Android SDK/ADB prerequisites.
- **Subagent-mediation** — driving a device is multi-step execution → always a dispatched subagent; main context stays a terse dashboard; verbose snapshots/logs live in subagents/files (cite SKILL.md §Subagent-mediated execution).
- **`.ad` scripts** — record-once/replay-many; one `.ad` per journey; stored with the session golden; reused across iterations and (UI-unchanged) future sessions.
- **Normalized checkpoint format** — copy the JSON shape from this plan's Conventions section, with the `computed`/`live` semantics, and point at `scripts/ad-capture.sh` as the adapter and `scripts/compare-golden.py` as the comparator.
- **Scope-every-command** — with two devices (live A/B), every `agent-device`/`adb` call is device-scoped (cite the autopilot dual-device lesson, but do not depend on autopilot).

- [ ] **Step 2: Structural test**

Run: `cd ../claude-code-skills-parity-loop && claude plugin validate .`
Expected: validation passes (no errors).

- [ ] **Step 3: Consistency test**

Run: `grep -l "compare-golden.py" SKILL_DIR/references/agent-device.md && grep -c "computed" SKILL_DIR/references/agent-device.md`
Expected: the file path prints and `computed` appears ≥1.

- [ ] **Step 4: Commit**

```bash
git add SKILL_DIR/references/agent-device.md
git commit -m "docs(kmm): agent-device reference (command surface, .ad, normalized format)"
```

### Task 2.2: `references/runtime-golden.md`

**Files:**
- Create: `SKILL_DIR/references/runtime-golden.md`

- [ ] **Step 1: Write the reference**

Create `SKILL_DIR/references/runtime-golden.md` with exactly these sections:
- **What the golden is** — a frozen runtime behavioral contract: real network wires + computed UI outputs per journey checkpoint, captured on master, additive to (not a replacement for) unit baselines.
- **Storage layout** — `.kmm/migrations/kmm/<feature>-<depth>/golden/<journey>/<checkpoint>/` with `checkpoint.json` (normalized) + `wires/*.json` + `screenshot.png` + `logcat.txt`. Gitignored (under `migrations/`).
- **PII gate (BLOCKING, trading data)** — verbatim rule: *"Before any golden is written, run `scripts/scrub-pii.py --gate <golden-dir>` (must be gitignored) and `--scan` each wire (report PII classes to the user). The golden is never committed and never embedded in the PR. Only shareable artifacts (report/PR text) are passed through `--scrub`; golden wires are left intact (replay needs them)."*
- **Masking policy (verbatim):** *"Never mask a value the migrated code computes (P&L, totals, derived prices, order values) — that is the headline signal. Mask only an externally-fed live feed not derived from migrated logic (raw streaming tick, self-re-rendering chart axis). Replay freezes inputs, so for replayed journeys there is nothing to mask; masking applies only to the live-A/B exception path."*
- **Replay vs live decision rule** — replay is the default (deterministic, exact computed-value diff, no login/real-money risk, serialization-under-R8 verified); live A/B + narrow masking is the exception for un-recordable streaming surfaces; a journey where replay is infeasible falls back to live and is flagged. Point at the M0 decision doc for the per-repo replay mechanism.
- **Freeze protection** — the golden freezes with the unit baselines (Phase C); editing a frozen golden requires the same migration-exception gate as a frozen baseline; the orchestrator confirms the exception before any subagent edits a frozen golden (hooks don't fire on subagent calls).

- [ ] **Step 2: Structural test**

Run: `claude plugin validate .`
Expected: passes.

- [ ] **Step 3: Consistency test**

Run: `grep -c "scrub-pii.py\|never mask\|Never mask\|replay" SKILL_DIR/references/runtime-golden.md`
Expected: ≥3.

- [ ] **Step 4: Commit**

```bash
git add SKILL_DIR/references/runtime-golden.md
git commit -m "docs(kmm): runtime-golden reference (capture, PII gate, masking, freeze)"
```

---

## Milestone 3 — Phase 0/A: user-journey catalog

### Task 3.1: Phase 0 authors `journeys.md`

**Files:**
- Modify: `SKILL_DIR/references/phases/phase-0-discovery.md`

- [ ] **Step 1: Add the journey-catalog sub-section**

In `phase-0-discovery.md`, add a sub-phase that produces `journeys.md` from the **user/QA lens**. Include this exact catalog template:
```markdown
## Journey catalog (journeys.md)
| Journey | User does | Expects to see | Type | Edge/negative paths |
|---|---|---|---|---|
| <name> | <user action sequence> | <observable outcome, plain language> | read-only / mutating | <empty / invalid / offline / back / re-entry> |
```
Rules to state in the section:
- Authored from what real users do + what a QA would try — **not** from the git diff.
- Negative/edge paths are first-class rows (OTP-lockout-style account-damaging paths excepted → declined gap unless a test account is confirmed).
- A Sonnet subagent drafts it from the Phase 0 navigation flow; orchestrator synthesizes.
- **Coverage-approval gate:** the user confirms the catalog before it freezes (it defines the entire downstream test surface). This is a new gate, distinct from the `project.md` diff-confirm; `journeys.md` is session-local + gitignored.

- [ ] **Step 2: Structural + consistency test**

Run: `claude plugin validate . && grep -c "journeys.md\|Coverage-approval\|user/QA lens\|read-only / mutating" SKILL_DIR/references/phases/phase-0-discovery.md`
Expected: validation passes; grep ≥2.

- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/references/phases/phase-0-discovery.md
git commit -m "feat(kmm): Phase 0 authors the user/QA-lens journey catalog"
```

### Task 3.2: Phase A enriches the catalog + diff coverage cross-check

**Files:**
- Modify: `SKILL_DIR/references/phases/phase-a-diagnostic.md`

- [ ] **Step 1: Add the coverage cross-check**

In `phase-a-diagnostic.md`, add: Phase A enriches each journey row with the per-file risk surfaces it touches, then runs a **diff coverage cross-check** — a subagent verifies every changed symbol from the Phase A plan is exercised by ≥1 journey. State verbatim: *"The diff-derived technical surfaces are no longer the heatmap; they are a coverage cross-check. A changed symbol covered by no journey is a catalog gap surfaced to the user — this keeps 'no exclusions' honest while the primary framing stays user-centric."*

- [ ] **Step 2: Structural + consistency test**

Run: `claude plugin validate . && grep -c "coverage cross-check\|catalog gap\|no exclusions" SKILL_DIR/references/phases/phase-a-diagnostic.md`
Expected: validation passes; grep ≥2.

- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/references/phases/phase-a-diagnostic.md
git commit -m "feat(kmm): Phase A enriches journeys + diff coverage cross-check"
```

---

## Milestone 4 — Phase B: runtime golden capture

### Task 4.1: Add the golden-capture sub-phase to Phase B

**Files:**
- Modify: `SKILL_DIR/references/phases/phase-b-baseline.md`

- [ ] **Step 1: Add the sub-phase**

After the unit-baseline sub-phases (before freeze), add **"B.x — Runtime golden capture"** stating:
- Drive the **master/current** build through every `journeys.md` journey with agent-device (via `scripts/ad-capture.sh`), recording real network wires + computed UI outputs + crash/log evidence at each checkpoint into the golden layout (cite `references/runtime-golden.md`).
- Tag each captured element `computed` vs `live` from the journey's expectation (computed = the value the migrated logic produces).
- **Run the PII gate** (`scripts/scrub-pii.py --gate` + `--scan`) before persisting; surface PII classes to the user; golden stays gitignored, never in the PR.
- Additive to unit baselines; both freeze together in Phase C.
- All device-driving is subagent-mediated; main context stays a dashboard.

- [ ] **Step 2: Structural + consistency test**

Run: `claude plugin validate . && grep -c "ad-capture.sh\|scrub-pii.py\|runtime-golden.md\|computed" SKILL_DIR/references/phases/phase-b-baseline.md`
Expected: validation passes; grep ≥3.

- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/references/phases/phase-b-baseline.md
git commit -m "feat(kmm): Phase B runtime golden capture (agent-device + PII gate)"
```

### Task 4.2: Add golden columns/rows to coverage.md schema in SKILL.md

**Files:**
- Modify: `plugins/kmm-migration-workflow/skills/kmm-migration/SKILL.md` (the `coverage.md columns` paragraph + Directory layout)

- [ ] **Step 1: Extend the directory layout + coverage schema**

In SKILL.md Directory layout, add under the session folder:
```
        ├── journeys.md             # Phase 0/A — user/QA-lens journey catalog (gitignored)
        ├── golden/                 # Phase B — runtime golden (wires + checkpoints; gitignored)
```
In the `coverage.md … columns` paragraph, add a note that each journey also has a golden-status entry (`captured` → `frozen`) tracked alongside file rows, and that the golden freezes with the baselines.

- [ ] **Step 2: Structural + consistency test**

Run: `claude plugin validate . && grep -c "journeys.md\|golden/" plugins/kmm-migration-workflow/skills/kmm-migration/SKILL.md`
Expected: validation passes; grep ≥2.

- [ ] **Step 3: Commit**

```bash
git add plugins/kmm-migration-workflow/skills/kmm-migration/SKILL.md
git commit -m "docs(kmm): SKILL.md layout + coverage schema for journeys/golden"
```

### Task 4.3: Record the replay note (GATED on M0 decision)

**Files:**
- Modify: `SKILL_DIR/references/phases/phase-b-baseline.md`

- [ ] **Step 1: Add the replay-readiness note**

> Prereq: Task 0.2 decision section exists.

Append to B.x: a one-paragraph note that the captured wires double as **replay inputs** for Phase I, citing the M0-selected mechanism (agent-device-native replay | external proxy | app-side interceptor) and the per-repo wiring recorded in `project.md` (base-URL/mock config from R2). State that journeys where replay is infeasible fall back to live A/B (flagged).

- [ ] **Step 2: Structural + consistency test**

Run: `claude plugin validate . && grep -c "replay" SKILL_DIR/references/phases/phase-b-baseline.md`
Expected: validation passes; grep ≥1.

- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/references/phases/phase-b-baseline.md
git commit -m "docs(kmm): Phase B replay-readiness note (per M0 mechanism)"
```

---

## Milestone 5 — Phase C: freeze the golden

### Task 5.1: Extend Phase C freeze to the golden

**Files:**
- Modify: `SKILL_DIR/references/phases/phase-c-freeze.md`

- [ ] **Step 1: Add golden to the freeze**

State that the freeze covers the `golden/` directory alongside the unit baselines: the golden's frozen-at SHA is recorded; editing a frozen golden requires a `.kmm/exceptions/*.md` entry (same gate as a frozen baseline); the orchestrator confirms the exception before dispatching any subagent edit to a frozen golden (hooks don't fire on subagent tool calls). Cite `references/runtime-golden.md` §Freeze protection.

- [ ] **Step 2: Structural + consistency test**

Run: `claude plugin validate . && grep -c "golden\|frozen" SKILL_DIR/references/phases/phase-c-freeze.md`
Expected: validation passes; grep ≥2.

- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/references/phases/phase-c-freeze.md
git commit -m "feat(kmm): Phase C freezes the runtime golden with the baselines"
```

---

## Milestone 6 — Phase F: heatmap reframe + agent-device upgrades

### Task 6.1: Heatmap = the journey catalog

**Files:**
- Modify: `SKILL_DIR/references/phases/phase-f-validation.md` (F.5 heatmap draft)

- [ ] **Step 1: Replace the heatmap source**

Rewrite F.5's heatmap-draft so the heatmap is **rendered from `journeys.md`** (user-readable rows: Journey / User does / Expects to see / Result=TBD), each row carrying a pointer to its frozen golden reference. Remove the diff-derived sourcing as the *primary* source (it now lives in Phase A as the coverage cross-check). Keep: Result column starts `TBD`, never pre-filled (filled in Phase I).

- [ ] **Step 2: Structural + consistency test**

Run: `claude plugin validate . && grep -c "journeys.md\|TBD" SKILL_DIR/references/phases/phase-f-validation.md`
Expected: validation passes; grep ≥2.

- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/references/phases/phase-f-validation.md
git commit -m "feat(kmm): Phase F heatmap rendered from the journey catalog"
```

### Task 6.2: agent-device smoke + network + crash upgrades

**Files:**
- Modify: `SKILL_DIR/references/phases/phase-f-validation.md` (F.5 smoke, F.3 HTTP checks)

- [ ] **Step 1: Upgrade the smoke + HTTP-inspection mechanism**

- F.5 smoke: replace the "structured-tap CLI / screenshot-and-report" smoke with agent-device (`open` → `snapshot` → `assert` known state, crash-free) using `agent-device logs`/crash capture as the gate evidence. Keep it a runtime-crash gate only (not a behavioral walk).
- F.3 HTTP checks: state that the "project's HTTP-inspection capability" used by the timeout-parity and server-registration-parity checks **is `agent-device network`** — concrete mechanism for real `tookMs`, timeout behavior, and host reachability.

- [ ] **Step 2: Structural + consistency test**

Run: `claude plugin validate . && grep -c "agent-device" SKILL_DIR/references/phases/phase-f-validation.md`
Expected: validation passes; grep ≥2.

- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/references/phases/phase-f-validation.md
git commit -m "feat(kmm): Phase F smoke/HTTP/crash via agent-device"
```

---

## Milestone 7 — Phase I: rewrite as the autonomous `/loop`

### Task 7.1: Rewrite the Phase I purpose + setup

**Files:**
- Modify: `SKILL_DIR/references/phases/phase-i-qa.md` (replace the delegation framing)

- [ ] **Step 1: Rewrite the purpose + setup sub-phase**

Replace the "hand off to kmm-qa-autopilot" framing with: **Phase I is a closed autonomous `/loop` that runs in-skill agent-device A/B parity and converges the heatmap to green.** Setup sub-phase (once, at loop entry):
- Reuse PR URL from `pr.md`.
- Build master baseline + migrated head as ProductionRelease APKs; **master built once, reused**; only the migrated side rebuilds after a fix.
- Open agent-device session(s); for live-A/B journeys only, the single manual prod login (session persists; force-stop+relaunch; never `clearState`). **Replay journeys need no login.**
- Seed per-journey `.ad` probes from the catalog; pair each with its frozen golden.

- [ ] **Step 2: Structural test** — `claude plugin validate .` → passes.
- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/references/phases/phase-i-qa.md
git commit -m "feat(kmm): Phase I — purpose + setup as in-skill agent-device loop"
```

### Task 7.2: Write the loop body + autonomy gates

**Files:**
- Modify: `SKILL_DIR/references/phases/phase-i-qa.md`

- [ ] **Step 1: Write the loop body**

Add the "Loop body (one iteration)" sub-phase, verbatim structure:
1. Per journey pick mode: **Replay (default)** — feed frozen wires to migrated build, replay `.ad`, capture via `ad-capture.sh`, **`compare-golden.py` exact-diff computed values (no masking)**; **Live A/B (exception)** — un-recordable streaming only, narrow semantic masking, never a computed value.
2. Classify each row 🟢/🔴/⚪ (anchor absent both = not green) /⚠️-eviction (live only).
3. Each 🔴: reproduce ≥2×; per-issue root-cause subagent (Sonnet small / Opus complex) with full context; classify parity-restoring bug / intentional change / known-false-positive.
4. **Fix parity-restoring bugs autonomously through the workflow:** failing-test-first → subagent edit → green → commit → retro; re-validate at Phase F.6 scope; rebuild migrated APK; re-run only the affected probe.
5. **Pause at a gate:** behavior-shifting fix (exception + user sign-off), dependency change, `migrate→hold` plan-flip, eviction (re-login), mutating/real-money journey.
6. Update heatmap Result cells + `qa.md` bug-fixing log.
7. *(Conditional iOS)* iOS UI path consumes migrated code → iOS forward-check via agent-device (crash-free + computed output matches frozen golden); else named gap. (Cite R4 detection.)

- [ ] **Step 2: Structural + consistency test**

Run: `claude plugin validate . && grep -c "compare-golden.py\|Replay\|Pause at a gate\|forward-check" SKILL_DIR/references/phases/phase-i-qa.md`
Expected: validation passes; grep ≥3.

- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/references/phases/phase-i-qa.md
git commit -m "feat(kmm): Phase I loop body + autonomy gates + iOS forward-check"
```

### Task 7.3: Write the completion promise + convergence (GATED on M0)

**Files:**
- Modify: `SKILL_DIR/references/phases/phase-i-qa.md`

- [ ] **Step 1: Write the convergence/exit section**

> Prereq: Task 0.2 decision exists (replay mechanism referenced here).

Add the **`/loop` completion promise** verbatim: *"Every catalog journey is 🟢 with a real anchor reached, zero open 🔴, zero ⚪-indeterminate, the iOS forward-check passed-or-is-a-named-gap, and any remaining finding is an explicitly user-deferred recorded follow-up."* Plus: a **max-iterations safety cap** that **pauses and surfaces** (never false-passes); anti-false-exit guards (empty baseline↔PR diff = hard stop; anchor-absent-on-both = ⚪ not 🟢); a note that emitting the promise while it is not genuinely true is prohibited. Then: Phase I retro (blocking) + session close-out unchanged.

State how `/loop` is invoked: the skill drives the loop via the harness `/loop` mechanism with the completion promise as the exit condition; each iteration re-enters the loop body until the promise is genuinely true or a gate/cap pauses it.

- [ ] **Step 2: Structural + consistency test**

Run: `claude plugin validate . && grep -c "completion promise\|max-iterations\|user-deferred" SKILL_DIR/references/phases/phase-i-qa.md`
Expected: validation passes; grep ≥2.

- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/references/phases/phase-i-qa.md
git commit -m "feat(kmm): Phase I completion promise + convergence guards"
```

### Task 7.4: Update the Phase I gates + output sections

**Files:**
- Modify: `SKILL_DIR/references/phases/phase-i-qa.md` (Phase-specific gates + Output: qa.md)

- [ ] **Step 1: Rewrite gates + output**

- Phase-specific gates: replace "autopilot suggested, never auto-launched" with the loop's gates (every fix through the workflow; loop pauses at the human-gated classes; converges on the completion promise or pauses at the cap; replay-default/live-exception; PII gate honored; iOS forward-check passed-or-named-gap; retro blocking).
- Output `qa.md`: add the per-journey verdict table (replay/live, 🟢/🔴/⚪, computed values compared, masked count) + the bug-fixing log; note `qa.md` is gitignored working-tree-only.

- [ ] **Step 2: Structural test** — `claude plugin validate .` → passes.
- [ ] **Step 3: Commit**

```bash
git add SKILL_DIR/references/phases/phase-i-qa.md
git commit -m "feat(kmm): Phase I gates + qa.md output for the loop"
```

---

## Milestone 8 — SKILL.md integration + version bump + validate + README

### Task 8.1: Update SKILL.md phase table, realistic-expectations, tooling note

**Files:**
- Modify: `plugins/kmm-migration-workflow/skills/kmm-migration/SKILL.md`

- [ ] **Step 1: Edit the three sections**

- **Phases overview table:** Phase I row → "Parity-QA loop — in-skill agent-device A/B parity (replay-primary), fix parity-restoring bugs through the workflow until the heatmap is green; conditional iOS forward-check." Phase 0/A/B/F rows updated to mention journeys.md / golden / catalog-heatmap.
- **Realistic expectations paragraph:** replace "Parity QA is no longer inside this skill … Phase I hands off to kmm-qa-autopilot" with: Phase I is an in-skill autonomous loop that replays the runtime golden against the migrated build and fixes parity-restoring bugs through the workflow until green; deterministic replay makes computed financial values comparable to the digit; live A/B is the narrow exception.
- **Tooling discipline:** add a bullet that agent-device is the device-driving + network/crash-capture mechanism; all runs subagent-mediated; cite `references/agent-device.md` and `references/runtime-golden.md`.

- [ ] **Step 2: Structural + consistency test**

Run: `claude plugin validate . && grep -c "agent-device\|journeys\|golden\|replay" plugins/kmm-migration-workflow/skills/kmm-migration/SKILL.md`
Expected: validation passes; grep ≥4.

- [ ] **Step 3: Commit**

```bash
git add plugins/kmm-migration-workflow/skills/kmm-migration/SKILL.md
git commit -m "docs(kmm): SKILL.md phase table + expectations + agent-device tooling"
```

### Task 8.2: Four-place version bump (lockstep) + README description

**Files:**
- Modify: `plugins/kmm-migration-workflow/.claude-plugin/plugin.json` (`1.12.0` → `1.13.0`)
- Modify: `.claude-plugin/marketplace.json` (kmm entry `1.12.0` → `1.13.0`; top-level `metadata.version` `1.36.0` → `1.37.0`)
- Modify: `README.md` (line 23 row: `1.12.0` → `1.13.0` + description)

- [ ] **Step 1: Bump plugin.json**

Set `"version": "1.13.0"` in `plugins/kmm-migration-workflow/.claude-plugin/plugin.json`.

- [ ] **Step 2: Bump marketplace.json (both places)**

In `.claude-plugin/marketplace.json`: the kmm-migration-workflow entry `"version": "1.12.0"` → `"1.13.0"`, and top-level `metadata.version` `"1.36.0"` → `"1.37.0"`.

- [ ] **Step 3: Update README row (line 23)**

Change the version cell to `1.13.0` and update the description tail from "…then parity-QA hand-off" to "…then an in-skill autonomous parity-QA loop (agent-device replay of a runtime golden) that fixes bugs through the workflow until the checklist is green."

- [ ] **Step 4: Verify lockstep**

Run:
```bash
grep '"version"' plugins/kmm-migration-workflow/.claude-plugin/plugin.json
grep -n '1.13.0\|1.37.0' .claude-plugin/marketplace.json
grep -n '1.13.0' README.md
```
Expected: plugin.json shows `1.13.0`; marketplace shows `1.13.0` (entry) and `1.37.0` (top-level); README line 23 shows `1.13.0`.

- [ ] **Step 5: Final structural test**

Run: `claude plugin validate .`
Expected: passes, no errors.

- [ ] **Step 6: Commit**

```bash
git add plugins/kmm-migration-workflow/.claude-plugin/plugin.json .claude-plugin/marketplace.json README.md
git commit -m "chore(kmm): bump kmm-migration-workflow 1.12.0 -> 1.13.0 (parity loop)"
```

### Task 8.3: Open the PR

- [ ] **Step 1: Push + PR**

Run:
```bash
git push -u origin feat/kmm-runtime-golden-parity-loop
gh pr create --title "feat(kmm): in-skill agent-device parity loop + runtime golden" \
  --body "$(cat <<'EOF'
Redesigns the kmm-migration final phase into a closed autonomous /loop driven by
agent-device. New: user/QA-lens journey catalog (Phase 0/A), runtime golden capture
on master (Phase B, PII-gated, frozen), heatmap rendered from the catalog + agent-device
smoke/HTTP/crash (Phase F), and Phase I rewritten as replay-primary A/B parity that fixes
parity-restoring bugs through the workflow until green. Trading-app: deterministic replay
makes computed financial values compare to the digit. Spec + plan + R1–R4 research doc included.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: PR opens.

---

## Self-Review

**1. Spec coverage** — every spec section maps to a task:
- §5.1 journey catalog → T3.1, T3.2 ✓
- §5.2 golden capture + PII + freeze → T4.1, T4.3, T5.1; scripts T1.1–1.4 ✓
- §5.3 heatmap reframe + smoke/network/crash → T6.1, T6.2 ✓
- §5.4 Phase I loop (setup/body/gates/convergence/iOS) → T7.1–7.4 ✓
- §6 replay harness research → M0 (T0.1, T0.2); gated T4.3, T7.3 ✓
- §7 agent-device surface → T2.1 ✓
- §8 broader upgrades → T6.2, T7.2, plus `.ad`/golden assets T2.x ✓
- §9 file impact + version bump → T4.2, T8.1, T8.2 ✓
- §1/§3/§10/§11 (problem/decisions/risks/success) → encoded in the reference content tasks ✓

**2. Placeholder scan** — no "TBD/TODO/handle edge cases" as work-deferral; the only `TBD` is the literal heatmap Result cell (a product requirement, not a plan gap). Script steps contain full runnable code. Markdown steps specify exact sections + verbatim load-bearing text.

**3. Type/name consistency** — `scripts/scrub-pii.py` (modes `--scan/--scrub/--gate`), `scripts/compare-golden.py` (exit 0/1/3 = PARITY/DIVERGENCE/INDETERMINATE), `scripts/ad-capture.sh` (`--device/--journey/--checkpoint/--anchor/--out`), and the normalized checkpoint format (`elements[].computed/live`, `anchor`) are used identically across tasks. Version targets `1.13.0`/`1.37.0` consistent in T8.2. `SKILL_DIR` defined once and reused.

**Known dependency:** M0 (research) gates the final wording of T4.3 and T7.3 only. All other tasks are independent of the unverified replay capability and degrade gracefully to live-A/B if R1 finds no native replay.
