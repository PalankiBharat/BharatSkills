# PR body — Migration Heatmap spec

Three layers produced from plan + `git diff --stat base..HEAD`.

## Layer A — Source-set summary table

| Source set | Files | Lines + | Lines - | Intensity |

Intensity thresholds:
- 🟩 < 100 lines delta
- 🟨 100 – 500 lines delta
- 🟥 > 500 lines delta

## Layer B — File tree with deltas

Truncated to 40 files; link to full diff.

## Layer C — Movement narrative

One line per file: `<file> : <old location> → <new location> (<note>)`.
