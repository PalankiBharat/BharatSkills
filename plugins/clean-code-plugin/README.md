# Clean Code Plugin for Claude Code

Professional code quality guidance following Robert C. Martin's "Clean Code" principles. Automatically applies best practices for naming, functions, classes, error handling, and testing across all programming languages.

## Features

### 🎯 Core Principles
- **Meaningful Names** - Intention-revealing variable, function, and class names
- **Small Functions** - Functions that do one thing well (5-20 lines)
- **Self-Documenting Code** - Code that speaks for itself
- **Proper Error Handling** - Exceptions over error codes, no null returns
- **DRY Principle** - Don't Repeat Yourself
- **Clean Tests** - F.I.R.S.T. principles (Fast, Independent, Repeatable, Self-Validating, Timely)

### 📚 Comprehensive Reference Library

**7 Deep-Dive Guides** loaded on-demand:
1. **naming.md** - Variable, function, class naming conventions
2. **functions.md** - Function design, arguments, side effects
3. **classes.md** - SOLID principles, cohesion, encapsulation
4. **comments.md** - When to comment (and when not to)
5. **formatting.md** - Code layout and structure
6. **error-handling.md** - Exception management, null handling
7. **testing.md** - TDD, clean tests, mocking patterns

### 🌐 Language Support

Works with all programming languages:
- Python, JavaScript/TypeScript, Java, C#
- Go, Rust, Ruby, PHP, Kotlin, Swift
- And more!

## Installation

### From Marketplace

```bash
# Add marketplace (if not already added)
claude plugin marketplace add <your-marketplace-url>

# Install the plugin
claude plugin install clean-code@<your-marketplace>
```

### From Git Repository

```bash
# Install directly from GitHub
claude plugin marketplace add github:<your-org>/clean-code-plugin

# Or from a specific branch/tag
claude plugin marketplace add github:<your-org>/clean-code-plugin#main
```

## Usage

The skill automatically activates when you write or refactor code:

```bash
# Writing new code
claude "Create a user authentication system"

# Refactoring existing code
claude "Refactor this function to be more maintainable" app.py

# Code review
claude "Review this codebase for clean code violations" src/

# Explicitly invoke the skill
claude "Following clean-code principles, write a REST API"
```

## Examples

### Before
```python
def f(u):
    if u['e'] and '@' in u['e']:
        db.save(u)
        return True
    return False
```

### After (with Clean Code guidance)
```python
def register_user(user_data):
    """Register a user if they have a valid email."""
    if is_valid_email(user_data):
        save_user_to_database(user_data)
        return True
    return False

def is_valid_email(user_data):
    email = user_data.get('email')
    return email and '@' in email

def save_user_to_database(user_data):
    database.save(user_data)
```

## Token Usage

The skill uses progressive disclosure for efficiency:

- **Idle**: ~100 tokens (metadata only)
- **Normal coding**: ~2,000-4,000 tokens (core + 1-2 references)
- **Deep refactoring**: ~4,000-6,000 tokens (core + 2-3 references)
- **Maximum**: ~10,800 tokens (all references loaded)

Most use cases stay in the 2,000-4,000 token range.

## What You Get

### Main Guide (SKILL.md)
Quick reference with essential principles:
- Meaningful naming rules
- Small function guidelines
- Self-documenting code patterns
- Error handling basics
- Code organization best practices
- Review checklist

### Reference Library (references/)
Deep-dive guides for specific topics:
- Comprehensive naming conventions with examples
- Function design patterns and anti-patterns
- SOLID principles and class design
- Comment best practices (good vs. bad)
- Vertical and horizontal formatting
- Exception management and null handling
- TDD and clean testing practices

## Code Review Checklist

When reviewing code, the skill helps you check:

- ✅ Names reveal intent without comments
- ✅ Functions are small and do one thing
- ✅ No duplicate code (DRY)
- ✅ Proper error handling (no ignored exceptions)
- ✅ Tests exist and pass
- ✅ No "clever" code - clarity over cleverness
- ✅ Consistent formatting and style
- ✅ No commented-out code

## Contributing

This plugin is based on Robert C. Martin's "Clean Code: A Handbook of Agile Software Craftsmanship".

To suggest improvements or report issues, please contact your marketplace administrator.

## License

See LICENSE file for details.

## Credits

Based on "Clean Code" by Robert C. Martin (Uncle Bob).
Skill created for the Claude Code community.

---

**Make your code professional. Make it clean. 🧹✨**
