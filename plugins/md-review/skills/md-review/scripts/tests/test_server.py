import json, os, sys, threading, tempfile, unittest, urllib.request, urllib.error

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import serve  # noqa: E402

_INDEX = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "index.html")


class ServerTest(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self._dir.name, "doc.md")
        with open(self.path, "w", encoding="utf-8") as f:
            f.write("# Hi\n")
        self.server = serve.build_server(self.path, idle_seconds=600)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self._dir.cleanup()

    def _get(self, path):
        return json.loads(urllib.request.urlopen(f"http://127.0.0.1:{self.port}{path}").read())

    def _post(self, path, payload):
        req = urllib.request.Request(
            f"http://127.0.0.1:{self.port}{path}",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        return urllib.request.urlopen(req)

    def test_api_doc_returns_markdown(self):
        self.assertEqual(self._get("/api/doc")["markdown"], "# Hi\n")

    def test_api_save_writes_file(self):
        base = self._get("/api/doc")["hash"]
        res = json.loads(self._post("/api/save", {"markdown": "# Bye\n", "baseHash": base}).read())
        self.assertTrue(res["ok"])
        with open(self.path, encoding="utf-8") as f:
            self.assertEqual(f.read(), "# Bye\n")

    def test_api_save_conflict_returns_409(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self._post("/api/save", {"markdown": "x\n", "baseHash": "stale"})
        self.assertEqual(ctx.exception.code, 409)
        self.assertEqual(json.loads(ctx.exception.read())["error"], "conflict")
        with open(self.path, encoding="utf-8") as f:
            self.assertEqual(f.read(), "# Hi\n")  # unchanged

    @unittest.skipUnless(os.path.isfile(_INDEX), "index.html not built yet (Task 5)")
    def test_root_serves_index_html(self):
        html = urllib.request.urlopen(f"http://127.0.0.1:{self.port}/").read().decode()
        self.assertIn("<article", html)
        self.assertIn('id="doc"', html)


if __name__ == "__main__":
    unittest.main()
