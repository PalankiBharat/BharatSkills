# QA Loop Orchestration

## Consumer lifecycle

Each test iteration requires a FRESH Claude session. This is non-negotiable
because the plugin system caches hook scripts and skill files at session start.

### Launch sequence

```bash
# 1. Kill existing session
tmux send-keys -t <pane> C-c
sleep 1
tmux send-keys -t <pane> "exit" Enter 2>/dev/null
sleep 2

# 2. Clean workspace
rm -rf /tmp/skill-tester-workspace && mkdir -p /tmp/skill-tester-workspace

# 3. Launch fresh Claude (bypass permissions to avoid blocking)
tmux send-keys -t <pane> "cd /tmp/skill-tester-workspace && claude --dangerously-skip-permissions" Enter

# 4. Wait for boot (watch for the prompt)
sleep 7

# 5. Send test prompt
tmux send-keys -t <pane> "<prompt>" Enter
```

### Completion detection

Poll the consumer pane every 10-15 seconds:

```bash
tmux capture-pane -t <pane> -p -S -80
```

The consumer has finished when:
- The Claude prompt (`❯`) appears after output
- The status line shows idle/low token count
- No "Running..." or "Thinking..." indicators

### Permission handling

If the captured output shows a permission prompt:
- "Do you want to create/overwrite" → Send `Enter` to approve
- "Do you want to proceed" → Send `Enter` to approve

### Output collection

After completion, collect TWO things:
1. The tmux pane output (captures Claude's explanation)
2. The actual file(s) written (read directly from `/tmp/skill-tester-workspace/`)

The FILE content is the primary validation target. The pane output is
secondary evidence (shows whether the skill's guidelines were mentioned).

## Developer lifecycle

The developer pane runs a persistent Claude session in the skill repo.
Send feedback as prompts:

```bash
tmux send-keys -t <pane> "<feedback>" Enter
```

Wait for the developer to finish (same completion detection as consumer).
Verify the commit happened:

```bash
# Check from orchestrator
cd <REPO_ROOT> && git log --oneline -1
```

## Cache update

After developer pushes, the orchestrator must sync the cache:

```bash
# Copy to versioned cache directory
cp -r <PLUGIN_DIR> ~/.claude/plugins/cache/punchhq-skills/<name>/<version>/

# Copy to marketplaces directory (this is what hooks read from)
cp -r <PLUGIN_DIR>/* ~/.claude/plugins/marketplaces/punchhq-skills/plugins/<plugin-dir>/
```

Both directories must be updated. The marketplaces directory is what the
hook system reads from at session start.

## Timing budget

Per iteration:
- Consumer boot: 5-8s
- Test execution: 30-90s (depends on complexity)
- Capture + validation: 5-10s
- Developer fix: 30-60s
- Cache update: 2s
- Total: ~2-3 minutes per iteration

Budget 15-20 minutes for a full QA run (3 prompts × ~5 iterations worst case).
