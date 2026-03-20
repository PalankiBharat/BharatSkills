# QA Analysis Orchestrator

Coordinates QA-level analysis by running all QA micro-skills in sequence. Think like a senior QA engineer who is trying to break the feature.

## Execution order

1. Read and apply `qa/user-test-cases.md` — user-facing test scenarios
2. Read and apply `qa/feature-questions.md` — questions a QA would ask the developer
3. Read and apply `qa/ux-edge-cases.md` — UX and platform edge cases

## Context passing

Each micro-skill receives:
- The original feature spec
- The story clarification output
- The domain analysis output (to avoid duplicating domain test cases)
- The tech analysis output (to understand the implementation approach)
- Output from previous QA micro-skills

## QA perspective

The QA analysis differs from Domain and Tech analysis in one key way: it thinks from the USER's perspective. Every test case starts with "As a user, I..." — not "The system should..." or "The API returns...".

The QA analysis should also catch gaps BETWEEN domain and tech — cases where the business rule is clear and the tech implementation is correct, but the USER EXPERIENCE falls through the cracks.

## Output aggregation

Combine all three micro-skill outputs under a single "QA Analysis" section with subsections for User Test Cases, QA Questions, and UX Edge Cases.
