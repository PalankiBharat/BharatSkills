import json, subprocess, sys, os, tempfile

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "scrub-pii.py")

def run(args, expect_code=None):
    p = subprocess.run([sys.executable, SCRIPT, *args], capture_output=True, text=True)
    if expect_code is not None:
        assert p.returncode == expect_code, f"code {p.returncode}, out={p.stdout} err={p.stderr}"
    return p

def test_detects_pii_classes_in_golden():
    with tempfile.TemporaryDirectory() as d:
        wires = os.path.join(d, "wires.json")
        with open(wires, "w") as f:
            json.dump({"phone": "9876543210", "token": "Bearer eyJhbGciOi.JIUzI1.abc",
                       "pan": "ABCDE1234F", "balance": "12000.50"}, f)
        # --scan reports PII classes found, exit 0 (report-only); names the classes
        p = run(["--scan", wires], expect_code=0)
        for cls in ("phone", "auth_token", "pan"):
            assert cls in p.stdout, f"{cls} not reported: {p.stdout}"
        assert "balance" not in p.stdout  # a financial value is NOT pii

def test_scrub_redacts_for_shareable_artifact():
    with tempfile.TemporaryDirectory() as d:
        art = os.path.join(d, "report.md")
        with open(art, "w") as f:
            f.write("user 9876543210 saw token Bearer eyJhbGciOi.JIUzI1.abc and PAN ABCDE1234F")
        run(["--scrub", art], expect_code=0)
        out = open(art).read()
        assert "9876543210" not in out and "[REDACTED:phone]" in out
        assert "ABCDE1234F" not in out and "[REDACTED:pan]" in out
        assert "eyJhbGciOi" not in out

def test_gate_fails_when_golden_path_not_gitignored():
    # --gate <dir>: exit 2 if the dir is NOT git-ignored (golden must never be committable)
    p = run(["--gate", "/definitely/not/ignored/golden"], expect_code=2)
    assert "not gitignored" in (p.stdout + p.stderr).lower()

if __name__ == "__main__":
    test_detects_pii_classes_in_golden()
    test_scrub_redacts_for_shareable_artifact()
    test_gate_fails_when_golden_path_not_gitignored()
    print("ok")
