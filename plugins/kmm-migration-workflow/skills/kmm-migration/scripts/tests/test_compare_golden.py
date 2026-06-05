import json, subprocess, sys, os, tempfile

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "compare-golden.py")

def write(d, name, obj):
    p = os.path.join(d, name)
    with open(p, "w") as f: json.dump(obj, f)
    return p

def run(golden, candidate):
    return subprocess.run([sys.executable, SCRIPT, golden, candidate], capture_output=True, text=True)

def base(total="₹1,200.50"):
    return {"journey": "holdings", "checkpoint": "c1", "anchor": "txt_total",
            "elements": [
                {"ref": "txt_total", "role": "text", "text": total, "computed": True, "live": False},
                {"ref": "ticker", "role": "text", "text": "22,140.05", "computed": False, "live": True},
            ]}

def test_identical_is_parity():
    with tempfile.TemporaryDirectory() as d:
        g = write(d, "g.json", base()); c = write(d, "c.json", base())
        p = run(g, c)
        assert p.returncode == 0 and "PARITY" in p.stdout, p.stdout

def test_computed_value_divergence_is_red():
    with tempfile.TemporaryDirectory() as d:
        g = write(d, "g.json", base("₹1,200.50")); c = write(d, "c.json", base("₹1,020.50"))
        p = run(g, c)
        assert p.returncode == 1 and "DIVERGENCE" in p.stdout, p.stdout
        assert "txt_total" in p.stdout

def test_live_field_difference_is_ignored():
    with tempfile.TemporaryDirectory() as d:
        g = base(); c = base()
        c["elements"][1]["text"] = "22,155.90"  # live ticker moved — must NOT fail
        gp = write(d, "g.json", g); cp = write(d, "c.json", c)
        p = run(gp, cp)
        assert p.returncode == 0 and "PARITY" in p.stdout, p.stdout

def test_anchor_absent_on_candidate_is_indeterminate():
    with tempfile.TemporaryDirectory() as d:
        g = base(); c = base()
        c["elements"] = [e for e in c["elements"] if e["ref"] != "txt_total"]
        gp = write(d, "g.json", g); cp = write(d, "c.json", c)
        p = run(gp, cp)
        assert p.returncode == 3 and "INDETERMINATE" in p.stdout, p.stdout

if __name__ == "__main__":
    test_identical_is_parity()
    test_computed_value_divergence_is_red()
    test_live_field_difference_is_ignored()
    test_anchor_absent_on_candidate_is_indeterminate()
    print("ok")
