# Dual-Emulator Setup & Locking — Reference

The parity run drives **two** emulators at once: **A = master build**, **B = PR build**. They
must be separate devices because master and a KMM-migration PR build the *same* applicationId
(`com.marketpulse.sniper.vte`, production flavor, no suffix) — the same package can't be
installed twice on one device.

## The one blessed way to bring up the two devices

```bash
bash scripts/ensure-two-emulators.sh "$RUN_DIR"
```

`$RUN_DIR` is the run's persistent directory (default `~/.kmm-parity/pr-<num>`). The script
writes the two locked serials to `$RUN_DIR/locks/lock-a` and `$RUN_DIR/locks/lock-b`.

**Policy (by running-emulator count):**
- **0 running** → create `kmm_parity_a` + `kmm_parity_b` (with `hw.keyboard = yes`) and boot both **visible**, lock A + B.
- **1 running** → lock it as A, boot a second visible one for B.
- **2 running** → lock both (A = lower serial, B = higher). Never opens a third.
- **3+ running** → refuse and ask. Override anytime with `export KMM_PARITY_A=<serial> KMM_PARITY_B=<serial>`.

## Non-negotiable rules (same spirit as single-device QA, doubled)

- **Visible only.** Never `-no-window`. The user must watch both runs and perform the manual login on each.
- **`hw.keyboard = yes`** on both AVDs (the script sets it). Without it the host keyboard is silently blocked and `inputText` / manual typing fail.
- **Hard scoping — every command names a serial.** There are two devices now; an unscoped `adb`/`maestro` call is ambiguous and will hit the wrong one or error.
  ```bash
  A="$(cat "$RUN_DIR/locks/lock-a")"   # master
  B="$(cat "$RUN_DIR/locks/lock-b")"   # PR
  adb -s "$A" shell ...
  maestro --device "$B" test <flow>
  ```
- **Never touch an emulator you didn't boot.** No `adb emu kill`, no `adb kill-server`. If a locked emulator dies mid-run, stop and report — don't grab a replacement, because A/B identity must stay stable for the comparison to mean anything.

## Build → device assignment

| Build | Worktree | Emulator | Lock file |
|-------|----------|----------|-----------|
| master (baseline, source of truth) | `$MASTER_WT` | A | `locks/lock-a` |
| PR head (candidate) | `$PR_WT` | B | `locks/lock-b` |

Install each with the serial scoped:
```bash
bash scripts/build-and-install.sh "$MASTER_WT" "$A" master
bash scripts/build-and-install.sh "$PR_WT"     "$B" pr
```

Two cold worktrees mean two cold `build/` dirs. `~/.gradle` (dependency cache) is shared
automatically and the script passes `--build-cache`, so the second build reuses the first
where it can — but expect the first ProductionDebug build to take several minutes.
