#!/usr/bin/env python3
"""
koin-binding-check.py — Deterministic Koin DI binding verification.
Generated during Phase 1 planning. Customize paths for your project.

Usage: python3 koin-binding-check.py [--koin-modules <glob>] [--shared-src <path>]
                                     [--platform-modules <glob,glob>]

Exit codes: 0 = all bindings resolved, 1 = missing bindings found

v2 improvements over v1:
  - Class-param parser does paren-counting, handles multiline constructors with
    default values containing parens (e.g., `= emptyList()`, `= { }`)
  - Inline-block pattern requires the Capitalized identifier to be followed by
    `(get` or `{`, not just any paren — avoids matching `Napier.d(...)`
  - Skip set extended with common Koin-provided platform types (Settings,
    HttpClient, Json, FileSystem, Clock, CoroutineDispatcher)
  - Reports each missing dep with the class that requires it
"""

import argparse
import glob
import os
import re
import sys


# Types that are typically provided by platform Koin modules or are primitives.
# Treated as "always resolved" — won't flag them missing.
SKIP = {
    # Kotlin primitives & stdlib
    'String', 'Int', 'Long', 'Float', 'Double', 'Boolean', 'Byte', 'Short', 'Char',
    'List', 'Map', 'Set', 'Unit', 'Any', 'Number', 'Nothing',
    'Array', 'MutableList', 'MutableMap', 'MutableSet',
    'Pair', 'Triple',
    # Android platform types (bound by androidContext / platform modules)
    'Context', 'Activity', 'Fragment', 'Application',
    # Coroutine types (typically provided or injected)
    'CoroutineScope', 'CoroutineDispatcher', 'CoroutineContext', 'Job',
    # Common KMM platform-provided types
    'Settings', 'HttpClient', 'Json', 'FileSystem', 'Clock',
    'Logger', 'Napier',  # Napier is global
    # kotlinx stdlib-ish
    'Flow', 'StateFlow', 'SharedFlow', 'Channel',
}


def find_koin_bindings(module_files):
    """Extract all types provided by Koin modules."""
    bindings = set()

    # Typed declarations: single<Type> { ... }, factory<Type> { ... }, viewModel<Type> { ... }
    pattern_typed = re.compile(
        r'(?:single|factory|viewModel)\s*<\s*(\w+)(?:<[^>]*>)?\s*>\s*[({]'
    )
    # bind TypeName::class
    pattern_bind = re.compile(r'bind\s+(\w+)::class')
    # *Of style: singleOf(::Foo), factoryOf(::Foo), viewModelOf(::Foo)
    pattern_of = re.compile(
        r'(?:singleOf|factoryOf|viewModelOf)\s*\(\s*::(\w+)\s*\)'
    )
    # Inline: single { Foo(...) } — Capitalized identifier followed by `(get` or `( get`
    # Requires the call to start with a `get()` or `{` (Koin DSL), rejects generic
    # calls inside the block like `Napier.d(...)`
    pattern_inline = re.compile(
        r'(?:single|factory|viewModel)\s*(?:<[^>]+>)?\s*\{\s*(\b[A-Z]\w+)\s*\(\s*(?:get\b|\))'
    )

    for f in module_files:
        try:
            with open(f) as fh:
                content = fh.read()
        except (IOError, OSError):
            continue
        for m in pattern_typed.finditer(content):
            bindings.add(m.group(1))
        for m in pattern_bind.finditer(content):
            bindings.add(m.group(1))
        for m in pattern_of.finditer(content):
            bindings.add(m.group(1))
        for m in pattern_inline.finditer(content):
            bindings.add(m.group(1))

    return bindings


def _extract_class_params(content, class_start_idx):
    """Given the offset just after `class Foo`, read balanced parens to
    extract the parameter block. Returns the substring between the first
    `(` and its matching `)`, or None if no constructor."""
    # Skip whitespace and generic type params.
    i = class_start_idx
    depth = 0
    # Skip optional generic block <...>
    while i < len(content) and content[i] in ' \t\n':
        i += 1
    if i < len(content) and content[i] == '<':
        depth = 1
        i += 1
        while i < len(content) and depth > 0:
            if content[i] == '<':
                depth += 1
            elif content[i] == '>':
                depth -= 1
            i += 1
    while i < len(content) and content[i] in ' \t\n':
        i += 1
    if i >= len(content) or content[i] != '(':
        return None
    start = i + 1
    depth = 1
    i = start
    while i < len(content) and depth > 0:
        c = content[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return content[start:i]
        i += 1
    return None


def find_injected_deps(shared_src):
    """Extract constructor dependencies from shared module classes via
    proper paren-counting (not regex). Captures types used in `val`/`var`
    constructor params, skipping default-value expressions that contain
    their own parens."""
    deps = {}  # class_name -> list of required type names

    # Match `class Foo` (optionally preceded by modifiers like `internal`,
    # `data`, `sealed`, etc.). Anchor to start of class declaration.
    class_head = re.compile(r'\b(?:data\s+|sealed\s+|open\s+|abstract\s+|internal\s+|public\s+|private\s+)*class\s+(\w+)')

    # Within a param block, each parameter starts with `[private|internal|public]? val|var name : Type`
    # We split by top-level commas (commas not inside parens/braces/angles).
    def split_top_level(params_str):
        out = []
        depth_paren = 0
        depth_brace = 0
        depth_angle = 0
        cur = []
        for c in params_str:
            if c == ',' and depth_paren == 0 and depth_brace == 0 and depth_angle == 0:
                out.append(''.join(cur).strip())
                cur = []
                continue
            if c == '(': depth_paren += 1
            elif c == ')': depth_paren -= 1
            elif c == '{': depth_brace += 1
            elif c == '}': depth_brace -= 1
            elif c == '<': depth_angle += 1
            elif c == '>': depth_angle -= 1
            cur.append(c)
        if cur:
            out.append(''.join(cur).strip())
        return out

    # Extract the leftmost simple type from a param spec.
    # Handles: `val foo: Bar`, `val foo: Bar<X>`, `val foo: Bar? = defaultExpr()`
    param_type = re.compile(
        r'(?:private\s+|internal\s+|public\s+|protected\s+)?(?:val|var)\s+\w+\s*:\s*(\w+)'
    )

    kt_files = glob.glob(os.path.join(shared_src, '**', '*.kt'), recursive=True)

    for f in kt_files:
        try:
            with open(f) as fh:
                content = fh.read()
        except (IOError, OSError):
            continue
        for m in class_head.finditer(content):
            class_name = m.group(1)
            params_str = _extract_class_params(content, m.end())
            if not params_str:
                continue
            param_specs = split_top_level(params_str)
            types = []
            for spec in param_specs:
                tm = param_type.search(spec)
                if tm:
                    t = tm.group(1)
                    if t not in SKIP:
                        types.append(t)
            if types:
                deps[class_name] = types

    return deps


def main():
    parser = argparse.ArgumentParser(description='Verify Koin DI bindings')
    parser.add_argument('--koin-modules', default='**/di/**Module*.kt',
                        help='Glob for Koin module files')
    parser.add_argument('--shared-src', default='shared/src/commonMain',
                        help='Path to shared source')
    parser.add_argument('--platform-modules', default='',
                        help='Additional glob for platform DI modules (comma-separated)')
    args = parser.parse_args()

    module_files = glob.glob(args.koin_modules, recursive=True)
    if args.platform_modules:
        for pattern in args.platform_modules.split(','):
            module_files.extend(glob.glob(pattern.strip(), recursive=True))

    if not module_files:
        print(f"WARN: No Koin module files found matching '{args.koin_modules}'")
        print("RESULT: SKIP — no Koin modules to check")
        sys.exit(0)

    print("=== Koin Binding Check (v2) ===")
    print(f"Module files: {len(module_files)}")
    print(f"Shared source: {args.shared_src}")
    print()

    bindings = find_koin_bindings(module_files)
    print(f"Bindings found: {len(bindings)}")
    for b in sorted(bindings):
        print(f"  ✓ {b}")
    print()

    deps = find_injected_deps(args.shared_src)
    print(f"Classes with injected deps: {len(deps)}")

    fail = False
    missing = []
    for class_name, required in sorted(deps.items()):
        for req in required:
            if req not in bindings:
                missing.append((class_name, req))
                fail = True

    for class_name, req in missing:
        print(f"  FAIL: {class_name} needs {req} — no Koin binding found")

    print()
    if fail:
        print(f"RESULT: FAIL — {len(missing)} missing Koin binding(s)")
        sys.exit(1)
    print("RESULT: PASS — all injected dependencies have Koin bindings")
    sys.exit(0)


if __name__ == '__main__':
    main()
