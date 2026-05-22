---
name: heap-dump-compare
description: >
  Compare two (or more) Android `.hprof` heap dumps and present the differences
  as a side-by-side table the user can act on. Use this skill whenever the user
  gives you one or more `.hprof` files (or pair-directories from the
  heap-dump-pair skill) and asks any version of "compare these", "diff these
  hprofs", "what's different", "what changed", "show me the heap diff", "find
  what's growing", "histogram diff", or hands over a pair plus a baseline and
  asks for analysis. Works for one pair (t0 vs t5 growth on a single build) or
  two pairs (A/B comparison between two builds). The skill's job is bounded:
  convert the dumps, extract per-class histograms, present a clear comparison
  table, and stop. It does NOT diagnose root causes, label findings as bugs,
  or recommend fixes — the user decides what to do with the data once they
  have it. If the user's intent or inputs are ambiguous (no second heap given,
  no stated goal, missing t0 or t5 in a pair), use AskUserQuestion to clarify
  before running.
---

# Heap Dump Compare

## What this skill does (and doesn't)

**Does:** convert Android `.hprof` to standard JVM format, extract a per-class
histogram (instances + shallow bytes) for each dump, and present a side-by-side
comparison table the user can scan and reason about.

**Doesn't:** speculate about root cause, label any finding as a bug, recommend
fixes, or push the user toward a conclusion. Once the table is on screen, the
skill's job is done — the user takes over from there. Your role is to extract
something valuable out of the heaps; theirs is to decide what to do with it.

This split matters because heap diffs often look damning at first glance and
turn out to be session-shape (different tick rates, different active surfaces,
different time-of-day), or look benign and turn out to be a leak. Premature
interpretation by the skill nudges users toward bad fixes. Stay neutral.

## When the inputs aren't clear, interview — don't guess

Common ambiguities and how to handle them:

| Situation | Use AskUserQuestion |
|---|---|
| User points at one `.hprof` file (no pair, no baseline) | Ask: is this a single-snapshot inspection, or do they want to compare against a baseline file/pair they haven't named yet? |
| User points at one pair-dir (t0 + t5) without saying what to look for | Ask: are they looking at single-build growth, or do they want to compare against a second pair-dir? |
| Two pair-dirs but the dir names don't make the labels obvious | Ask: which one is the "A" / control / baseline, and which is the "B" / variant? |
| User says "compare these" but the directory has 3+ `.hprof` files | List the files and ask which pair(s) to compare. |
| User states a goal that needs targeted output (e.g. "find what's leaking", "compare native usage", "see if Compose got worse") | Ask if they want the default top-N-by-byte-delta view or a category-filtered view (Ktor, coroutines, native allocs, Compose, etc.). |

When asking, prefer multi-choice options (`AskUserQuestion`'s built-in `Other`
escape hatch is fine for free text). One round of clarifying questions is
cheaper than running the wrong comparison.

If the user explicitly told you the goal up front ("compare master vs branch
heaps to find what's different"), don't ask redundant questions — just run.

## The flow

### 1. Locate and label the inputs

The user typically hands over:

- A directory containing `*t0min*.hprof` and `*t5min*.hprof` — treat as a pair
- A `.hprof` path
- Two of either of the above (for A/B comparison)

For pair-dirs, derive the label from the directory basename. If two pair-dirs
have similar basenames and the A/B mapping is ambiguous, ask.

### 2. Run the wrapper

```bash
bash scripts/compare-heap-dumps.sh <inputs...> [--top N] [--label-a NAME --label-b NAME]
```

Examples — pick whichever shape matches the inputs:

```bash
# Single-build growth (one pair-dir)
bash scripts/compare-heap-dumps.sh ~/dev/heap-dumps/build-A/

# A/B comparison (two pair-dirs)
bash scripts/compare-heap-dumps.sh \
  --label-a master --label-b branch \
  ~/dev/heap-dumps/build-A/ ~/dev/heap-dumps/build-B/

# A/B comparison with four explicit hprof paths
bash scripts/compare-heap-dumps.sh \
  --label-a master --label-b branch \
  ~/dev/heap-dumps/A-t0.hprof ~/dev/heap-dumps/A-t5.hprof \
  ~/dev/heap-dumps/B-t0.hprof ~/dev/heap-dumps/B-t5.hprof
```

The wrapper handles conversion (Android `.hprof` → JVM `.hprof` via
`hprof-conv`), histogram extraction, and the per-class diff. On re-runs it
skips already-converted files (mtime check), so iterating with different
`--top N` or different labels is cheap.

### 3. Present the result as a table

Don't dump the wrapper's raw output back to the user. Read it, then render
a compact side-by-side table they can scan. The default presentation has
two parts:

**Part A — totals overview** (always include):

| Metric | `<label A>` | `<label B>` | Δ (B−A) |
|---|---:|---:|---:|
| Heap bytes at t0 | … | … | … |
| Heap bytes at t5 | … | … | … |
| 5-min growth bytes | … | … | … |
| Object count at t5 | … | … | … |
| Class count at t5 | … | … | … |

**Part B — top classes by delta** (the main table):

| Class | `<label A>` Δobj | `<label B>` Δobj | extra on B | ratio |
|---|---:|---:|---:|---:|
| `<class name>` | … | … | … | … |

For single-build (growth) mode, the table has one delta column instead of two:

| Class | t0 objs | t5 objs | Δobj | Δbytes |
|---|---:|---:|---:|---:|

Keep the table to ~30 rows by default (the wrapper's `--top` flag controls
this). If the user has a stated goal that maps to a category bucket (Ktor /
coroutines / native allocs / Compose / etc.), include a second table filtered
to that category. The wrapper already emits one "category breakdown" panel in
A/B mode — just transcribe whichever bucket(s) the user cares about.

### 4. Surface anomalies neutrally — don't editorialise

After the table, you may briefly call out 2–3 rows where the delta or ratio
is unusually large compared to the rest of the table. Phrase these as
observations, not conclusions:

- Good: *"`<some.package.SomeClass>` is 0 on A and 73 on B — only on B."*
- Good: *"`java.util.HashMap$Node` is 10× higher on B (52,408 vs 5,103)."*
- Bad: *"B is leaking HashMaps — investigate the cache layer."*

If the user asks "what does this mean" or "is this a bug", that's a new
conversation — answer it then, with context. Don't preempt.

The user will read the table and form their own conclusion. If they want your
read, they'll ask. Don't volunteer a verdict.

### 5. Stop

The skill's contract ends at the table. Don't:

- Propose code fixes
- Recommend dependency changes
- Explain how to investigate further
- Speculate about session shape vs code regression

If the user's next message asks for any of those, that's a new task — handle
it then, with context. Until they ask, hand them the table and wait.

## Things to NOT do

- **Don't run a JVM heap analyzer on the raw Android hprof.** Standard `jhat`
  and Eclipse MAT reject or mis-parse Android hprofs because of ART-specific
  extensions. Always go through `hprof-conv` first — the wrapper does this
  automatically.
- **Don't compare dumps where the PID changed between t0 and t5.** Process
  restart between dumps means the histograms are from two different program
  instances. The `heap-dump-pair` skill flags PID changes; honor that flag and
  mention it to the user if so, then ask whether to proceed anyway.
- **Don't claim equivalence between two runs without checking session shape.**
  If total heap or object count differ by >2× between A and B, the runs likely
  weren't apples-to-apples — note that fact in the totals table comment, but
  still present the data.
- **Don't write the report file unless the user asked for one.** Default is to
  present the table inline. Save to disk only on explicit request.

## Prerequisites

- `hprof-conv` from the Android SDK platform-tools. Default path:
  `~/Library/Android/sdk/platform-tools/hprof-conv`. Override via
  `HPROF_CONV=/path/to/hprof-conv` in the environment if installed elsewhere.
- Python 3 (system Python on macOS works — no third-party packages required).

## File layout

```
heap-dump-compare/
├── SKILL.md
└── scripts/
    ├── compare-heap-dumps.sh   # orchestrator (the main entry point)
    ├── hprof_histogram.py      # JVM hprof → per-class CSV
    ├── diff_histograms.py      # CSV diff + categorized comparison
    └── buckets.json            # subsystem groupings for the category panel
```
