#!/usr/bin/env python3
"""PII/secret gate for the runtime golden (trading data).

Three modes:
  --scan <file>   Report which PII classes appear (report-only, exit 0). Used to
                  inform the user that the golden contains PII and must stay local.
  --scrub <file>  Redact PII in place for a SHAREABLE artifact (report / PR text).
                  Never run on golden wires — replay needs them intact.
  --gate <dir>    Exit 2 unless <dir> is git-ignored. The golden must never be
                  committable. Exit 0 when ignored.

Financial values (balances, amounts) are NOT PII and are never touched.
"""
import re, sys, subprocess

PATTERNS = {
    "phone":      re.compile(r"\b(?:\+?91[-\s]?)?[6-9]\d{9}\b"),
    "auth_token": re.compile(r"\b(?:Bearer\s+)?eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"),
    "pan":        re.compile(r"\b[A-Z]{5}[0-9]{4}[A-Z]\b"),
    "aadhaar":    re.compile(r"\b\d{4}\s?\d{4}\s?\d{4}\b"),
    "email":      re.compile(r"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b"),
}

def scan(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    found = [name for name, rx in PATTERNS.items() if rx.search(text)]
    if found:
        print("PII classes found: " + ", ".join(found))
    else:
        print("no PII classes found")
    return 0

def scrub(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    for name, rx in PATTERNS.items():
        text = rx.sub(f"[REDACTED:{name}]", text)
    open(path, "w", encoding="utf-8").write(text)
    print(f"scrubbed {path}")
    return 0

def gate(path):
    r = subprocess.run(["git", "check-ignore", "-q", path])
    if r.returncode == 0:
        print(f"ok: {path} is gitignored")
        return 0
    print(f"BLOCKED: {path} is not gitignored — the golden must never be committable", file=sys.stderr)
    return 2

def main(argv):
    if len(argv) != 3 or argv[1] not in ("--scan", "--scrub", "--gate"):
        print(__doc__); return 64
    return {"--scan": scan, "--scrub": scrub, "--gate": gate}[argv[1]](argv[2])

if __name__ == "__main__":
    sys.exit(main(sys.argv))
