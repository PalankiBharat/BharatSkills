# Tech Analysis Orchestrator

Coordinates technical analysis by running all tech micro-skills in sequence.

## Execution order

1. Read and apply `tech/code-context.md` — map affected files, modules, and architecture layers
2. Read and apply `tech/impact-analyzer.md` — identify which existing features are impacted
3. Read and apply `tech/tech-test-cases.md` — generate technical test cases
4. Read and apply `tech/edge-cases.md` — identify technical edge cases
5. Read and apply `tech/tech-stack.md` — stack-specific considerations

## Context passing

Each micro-skill receives:
- The original feature spec
- The story clarification output
- The domain analysis output (business rules inform technical decisions)
- Output from previous tech micro-skills

## Architecture context

Default tech stack is **Android with Kotlin, Jetpack Compose, Clean Architecture (Presentation → Domain → Data), Hilt DI, Room DB, Kotlin Coroutines/Flow, Retrofit**. The codebase follows SOLID principles and Gang of Four design patterns. When the user provides specific codebase context, use that instead.

## Output aggregation

Combine all five micro-skill outputs under a single "Tech Analysis" section with subsections for Code Context, Impact, Test Cases, Edge Cases, and Stack Considerations.
