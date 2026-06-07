# plugins/md-review/skills/md-review/scripts/tests/test_docstore.py
import hashlib, os, sys, tempfile, unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from docstore import read_doc, save_doc, ConflictError  # noqa: E402


def _write(d, text):
    p = os.path.join(d, "a.md")
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)
    return p


class DocstoreTest(unittest.TestCase):
    def test_read_doc_returns_markdown_and_sha256(self):
        with tempfile.TemporaryDirectory() as d:
            p = _write(d, "# Hi\n")
            doc = read_doc(p)
            self.assertEqual(doc["markdown"], "# Hi\n")
            self.assertEqual(doc["hash"], hashlib.sha256(b"# Hi\n").hexdigest())
            self.assertEqual(doc["path"], p)

    def test_save_doc_writes_when_hash_matches(self):
        with tempfile.TemporaryDirectory() as d:
            p = _write(d, "old\n")
            base = read_doc(p)["hash"]
            res = save_doc(p, "new\n", base)
            self.assertTrue(res["ok"])
            with open(p, encoding="utf-8") as f:
                self.assertEqual(f.read(), "new\n")
            self.assertEqual(res["hash"], hashlib.sha256(b"new\n").hexdigest())

    def test_save_doc_raises_conflict_when_hash_differs(self):
        with tempfile.TemporaryDirectory() as d:
            p = _write(d, "old\n")
            with self.assertRaises(ConflictError) as ctx:
                save_doc(p, "new\n", "stalehash")
            self.assertEqual(ctx.exception.current_hash, read_doc(p)["hash"])
            with open(p, encoding="utf-8") as f:
                self.assertEqual(f.read(), "old\n")  # unchanged

    def test_save_doc_force_overwrites_on_conflict(self):
        with tempfile.TemporaryDirectory() as d:
            p = _write(d, "old\n")
            res = save_doc(p, "new\n", "stalehash", force=True)
            self.assertTrue(res["ok"])
            with open(p, encoding="utf-8") as f:
                self.assertEqual(f.read(), "new\n")


if __name__ == "__main__":
    unittest.main()
