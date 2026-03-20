# Domain Analysis Orchestrator

Coordinates domain-level analysis by running all domain micro-skills in sequence.

## Execution order

1. Read and apply `domain/approval-checker.md` — identify all approvals and compliance requirements
2. Read and apply `domain/domain-questions.md` — generate business questions for stakeholders
3. Read and apply `domain/domain-test-cases.md` — generate domain-specific test scenarios

## Context passing

Each micro-skill receives:
- The original feature spec
- The story clarification output (assumptions, scope)
- Output from previous domain micro-skills (to avoid duplication)

## Domain context

Default domain is **trading/fintech** (Indian markets — NSE/BSE/MCX, broker APIs like Zerodha Kite, SEBI regulations). When the feature is clearly about a different domain, adapt the analysis accordingly but maintain the same thoroughness.

## Output aggregation

Combine all three micro-skill outputs under a single "Domain Analysis" section with subsections for Approvals, Questions, and Test Cases.
