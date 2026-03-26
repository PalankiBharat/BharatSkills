# Escalation Rules Reference

This file defines when and how to escalate blockers during gameplan execution.

---

## Never Work Around Blockers With Hacks

When the plan or requirements specify how something should work, implement it as specified. If you hit a blocker that makes the specified approach seem impossible, STOP and escalate — do not invent workarounds to keep the build green. Specifically:

- **No stubs or placeholder implementations** — don't create empty/mock implementations just to satisfy the compiler
- **No technology substitutions** — don't swap a specified dependency for a "simpler" alternative (e.g., in-memory DB instead of ObjectBox because you think it won't work on the target platform)
- **No feature omissions** — don't skip or simplify specified behavior to avoid a hard problem
- **No silent downgrades** — don't weaken types, remove nullability constraints, or broaden error handling to make things compile

---

## When to Escalate

If implementing a task as specified would require something you're unsure about (platform support, library compatibility, API availability), stop and present the user with:

1. **The blocker** — what you're trying to do and why it's not straightforward
2. **Options** (2-4), each with:
   - What it involves
   - Pros
   - Cons
   - Your confidence it will work
3. **Your recommendation** — which option you'd pick and why

Wait for the user to choose before proceeding.
