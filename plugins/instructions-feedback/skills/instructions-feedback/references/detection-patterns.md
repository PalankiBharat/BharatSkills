# Detection Patterns

Scan the current conversation from the start. For each user message, assess
whether it contains a **correction signal** that may warrant a rule update.

## Strong signals — raise as candidates

These are high-confidence indicators that the user is expressing a durable
preference, correction, or missed rule:

- Absolute directives: `always`, `never`, `going forward`, `from now on`,
  `next time`, `in future`, `every time`
- Explicit misses: `you missed`, `you forgot`, `you should have`,
  `you didn't`, `why didn't you`
- Negations of behavior: `don't <do X>`, `stop <behavior>`, `we never do X`
- Corrections with rationale: `actually`, `this is wrong because`,
  `that violates`, `that's not how we do it`
- Standard-setting: `our standard is`, `the rule is`, `we require`,
  `we always ensure`
- Principle naming: `this is principle <N>`, `this violates principle`,
  `this isn't <principle name>`

## Weak signals — flag but require corroboration

These *may* be corrections but are often just clarifications. Only surface
them as candidates if the user then restates a durable preference or the
same topic recurs multiple times in the session:

- User rephrasing a requirement after Claude's output
- User asking "why did you...?" followed by a different approach
- User providing a concrete example that contradicts Claude's general
  answer
- User correcting a single fact without implying a rule

## Non-signals — ignore

- Factual corrections about this specific task ("the file is at Y, not X")
  unless they hint at a broader pattern
- Questions the user asks to understand Claude's reasoning
- Follow-up task requests

## Classification

Once a candidate is detected, classify it:

| Classification | When to use | Example |
|---|---|---|
| `claude-md` | New operating rule or workflow step that applies across sessions | "always paste gradle output when you claim done" |
| `constitution` | Amendment to an existing principle or a genuinely new non-negotiable principle | "we should never expose MutableStateFlow publicly — make this a constitution rule" |
| `path-rule` | Narrow technical rule that only applies to a specific directory / file type | "in repositories always use `conflate` for tick streams" → concurrency.md |
| `memory-only` | Factual context or preference that doesn't change a rule but Claude should remember | "our Mixpanel project key is stored in BuildConfig.MP_KEY" |

If ambiguous between two classifications, pick the more conservative
(prefer `memory-only` over `claude-md`, prefer `claude-md` over
`constitution`).

## Grouping

If multiple candidates touch the same theme (e.g., three corrections about
concurrency patterns), offer to bundle them into a single issue with
multiple bullet points. Do not bundle across themes.

## Priority heuristic

- **P0** — behavior that caused (or nearly caused) an incident, data
  integrity risk, or production bug pattern the user explicitly flagged
- **P1** — a rule Claude violated more than once in the session, or a
  new principle that would prevent a recurring correction
- **P2** — clarification, wording tightening, or capture-for-the-record

When uncertain, pick P2.

## Output shape (pass to Phase 2)

For each candidate produce:

```
{
  "quote": "<verbatim user text, trimmed>",
  "interpretation": "<Claude's one-sentence summary>",
  "classification": "claude-md | constitution | path-rule | memory-only",
  "target_file": "<CLAUDE.md | .specify/memory/constitution.md | .claude/rules/compose.md | ...>",
  "proposed_title": "<short, imperative>",
  "priority": "P0 | P1 | P2",
  "rationale": "<1-2 sentence why this matters>",
  "proposed_amendment": "<concrete suggested wording or bullet>"
}
```
