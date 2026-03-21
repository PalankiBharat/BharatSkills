---
name: clean-code
description: Comprehensive guide for writing clean, maintainable code following Robert C. Martin's Clean Code principles. Use when writing any code, refactoring existing code, reviewing code, or when the user asks for clean code practices, code quality improvements, or software craftsmanship guidance. Covers naming, functions, comments, formatting, error handling, and general code organization principles.
---

# Clean Code

Write code that is readable, maintainable, and professional following Uncle Bob's Clean Code principles.

## Core Philosophy

**Clean code reads like well-written prose.** Code is read far more often than it is written. Optimize for the reader, not the writer.

## Essential Principles

### 1. Meaningful Names

Use intention-revealing names that explain why a variable exists, what it does, and how it's used:

```python
# Bad
d = 5  # elapsed time in days

# Good
elapsed_days = 5
```

**Rules:**
- Make distinctions meaningful (avoid `data`, `info`, `a1`, `a2`)
- Use pronounceable, searchable names
- Classes use nouns, functions use verbs
- One word per concept consistently
- No encodings (Hungarian notation is obsolete)

### 2. Small Functions

Functions should:
- **Do ONE thing** and do it well
- Be small (ideally 5-20 lines)
- Have descriptive names that explain what they do
- Take 0-3 arguments (fewer is better)
- Have no side effects
- Stay at one level of abstraction

```python
# Bad - does multiple things
def process_user_and_send_email(user_data, email_config):
    # validates, saves, sends email, logs
    pass

# Good - single responsibility
def validate_user(user_data): pass
def save_user(user): pass
def send_welcome_email(user): pass
```

### 3. Self-Documenting Code

Good code is self-documenting. Use comments only when code cannot express intent:

```python
# Bad - redundant comment
# Check if employee is eligible for benefits
if employee.age > 65:

# Good - expressive code
if employee.is_eligible_for_retirement():
```

### 4. Error Handling

- Use exceptions, not error codes
- Provide context with exceptions
- Don't return null; use Optional/Maybe patterns
- Don't pass null as arguments
- Fail fast and early

```python
# Good
def get_user(user_id):
    user = database.find_user(user_id)
    if not user:
        raise UserNotFoundError(f"User {user_id} not found")
    return user
```

### 5. DRY (Don't Repeat Yourself)

Duplication is the root of evil in software. Extract common logic into reusable functions.

### 6. Code Organization

- Functions should descend in abstraction level (stepdown rule)
- Group related concepts together
- Minimize vertical distance between related code
- Keep lines short (80-120 characters)
- Use blank lines to separate concepts

## Workflow for Writing Clean Code

1. **Write working code first** - Get it functional
2. **Refactor ruthlessly** - Apply clean code principles
3. **Name with care** - Spend time on meaningful names
4. **Extract functions** - Break down complex logic
5. **Remove comments** - Replace with expressive code
6. **Test thoroughly** - Ensure refactoring didn't break anything

## Code Review Checklist

When reviewing code (yours or others), check:

- [ ] Names reveal intent without comments
- [ ] Functions are small and do one thing
- [ ] No duplicate code (DRY)
- [ ] Proper error handling (no ignored exceptions)
- [ ] Tests exist and pass
- [ ] No "clever" code - prefer clarity over cleverness
- [ ] Consistent formatting and style
- [ ] No commented-out code

## Language-Agnostic Rules

These principles apply to **all programming languages**:

1. **Boy Scout Rule**: Leave code cleaner than you found it
2. **YAGNI**: You Aren't Gonna Need It - don't add premature features
3. **KISS**: Keep It Simple, Stupid
4. **Optimize for readability**: Code is for humans first, computers second

## Deep Dive References

For detailed guidelines on specific topics, see:

- **references/naming.md** - Variable, function, class naming conventions with examples
- **references/functions.md** - Function design, arguments, side effects, error handling
- **references/classes.md** - Class design, SOLID principles, cohesion, encapsulation
- **references/comments.md** - When and how to comment (and when not to)
- **references/formatting.md** - Code layout, vertical/horizontal formatting, team standards
- **references/error-handling.md** - Exception management, null handling, fail-fast patterns
- **references/testing.md** - Unit testing best practices, TDD, F.I.R.S.T. principles

Load these references when working on specific aspects for comprehensive guidance.
