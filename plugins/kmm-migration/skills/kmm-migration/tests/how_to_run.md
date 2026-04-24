# How to run pressure scenarios

V1 runs manually via Claude Code subagent dispatch. For each scenario:

1. Open a fresh Claude Code session (context: fork if available).
2. Load the skill via `/kmm-migration`.
3. Paste the prompt from the scenario file.
4. Record the agent's response.
5. Compare against Expected behaviour.
6. Tick or flag.

Repeat for each of Haiku, Sonnet, Opus.

V2 will add an automated harness.
