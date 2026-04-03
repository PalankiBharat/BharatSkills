#!/usr/bin/env python3
"""
koin-binding-check.py — Deterministic Koin DI binding verification.
Generated during Phase 1 planning. Customize paths for your project.

Usage: python3 koin-binding-check.py [--koin-modules <glob>] [--shared-src <path>]

Exit codes: 0 = all bindings resolved, 1 = missing bindings found
"""

import argparse
import glob
import os
import re
import sys


def find_koin_bindings(module_files):
    """Extract all types provided by Koin modules."""
    bindings = set()
    # Patterns: single { TypeName(...) }, factory { TypeName(...) }, viewModel { TypeName(...) }
    # Also: single<TypeName> { ... }, bind TypeName::class
    pattern_block = re.compile(r'(?:single|factory|viewModel|viewModelOf)\s*(?:<\s*(\w+)\s*>)?\s*\{')
    pattern_bind = re.compile(r'bind\s+(\w+)::class')
    pattern_of = re.compile(r'(?:singleOf|factoryOf|viewModelOf)\s*\(\s*::(\w+)\s*\)')

    for f in module_files:
        with open(f) as fh:
            content = fh.read()
            for m in pattern_block.finditer(content):
                if m.group(1):
                    bindings.add(m.group(1))
            for m in pattern_bind.finditer(content):
                bindings.add(m.group(1))
            for m in pattern_of.finditer(content):
                bindings.add(m.group(1))

            # Also extract the return type from the block: single { Foo(...) }
            inline_pattern = re.compile(r'(?:single|factory|viewModel)\s*\{[^}]*?(\b[A-Z]\w+)\s*\(')
            for m in inline_pattern.finditer(content):
                bindings.add(m.group(1))

    return bindings


def find_injected_deps(shared_src):
    """Extract constructor dependencies from shared module classes."""
    deps = {}  # class_name -> [list of required types]

    kt_files = glob.glob(os.path.join(shared_src, '**', '*.kt'), recursive=True)
    # Pattern: class Foo(private val bar: BarType, private val baz: BazType)
    class_pattern = re.compile(r'class\s+(\w+)\s*\(([^)]*)\)')
    param_pattern = re.compile(r'(?:private\s+)?(?:val|var)\s+\w+\s*:\s*(\w+)')

    for f in kt_files:
        with open(f) as fh:
            content = fh.read()
            for m in class_pattern.finditer(content):
                class_name = m.group(1)
                params_str = m.group(2)
                param_types = param_pattern.findall(params_str)
                # Filter out primitives and common stdlib types
                skip = {'String', 'Int', 'Long', 'Float', 'Double', 'Boolean', 'List', 'Map', 'Set', 'Unit', 'Any'}
                param_types = [t for t in param_types if t not in skip]
                if param_types:
                    deps[class_name] = param_types

    return deps


def main():
    parser = argparse.ArgumentParser(description='Verify Koin DI bindings')
    parser.add_argument('--koin-modules', default='**/di/**Module*.kt',
                        help='Glob pattern for Koin module files')
    parser.add_argument('--shared-src', default='shared/src/commonMain',
                        help='Path to shared source')
    parser.add_argument('--platform-modules', default='',
                        help='Additional glob for platform DI modules (comma-separated)')
    args = parser.parse_args()

    # Find Koin module files
    module_files = glob.glob(args.koin_modules, recursive=True)
    if args.platform_modules:
        for pattern in args.platform_modules.split(','):
            module_files.extend(glob.glob(pattern.strip(), recursive=True))

    if not module_files:
        print(f"WARN: No Koin module files found matching '{args.koin_modules}'")
        print("RESULT: SKIP — no Koin modules to check")
        sys.exit(0)

    print("=== Koin Binding Check ===")
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
    for class_name, required in sorted(deps.items()):
        for req in required:
            if req not in bindings:
                print(f"  FAIL: {class_name} needs {req} — no Koin binding found")
                fail = True
            else:
                print(f"  PASS: {class_name} needs {req} → bound")

    print()
    if fail:
        print("RESULT: FAIL — missing Koin bindings detected")
        sys.exit(1)
    else:
        print("RESULT: PASS — all injected dependencies have Koin bindings")
        sys.exit(0)


if __name__ == '__main__':
    main()
