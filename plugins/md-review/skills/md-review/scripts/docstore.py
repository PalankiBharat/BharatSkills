# plugins/md-review/skills/md-review/scripts/docstore.py
"""File I/O for md-review: read a Markdown file, save it back with a SHA-256 conflict guard."""
import hashlib


class ConflictError(Exception):
    """Raised when the file on disk changed since it was opened (hash mismatch)."""

    def __init__(self, current_hash):
        super().__init__("file changed on disk")
        self.current_hash = current_hash


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def hash_file(path: str) -> str:
    with open(path, "rb") as f:
        return _sha256(f.read())


def read_doc(path: str) -> dict:
    with open(path, "rb") as f:
        data = f.read()
    return {"path": path, "markdown": data.decode("utf-8"), "hash": _sha256(data)}


def save_doc(path: str, markdown: str, base_hash: str, force: bool = False) -> dict:
    if not force:
        on_disk = hash_file(path)
        if on_disk != base_hash:
            raise ConflictError(on_disk)
    data = markdown.encode("utf-8")
    with open(path, "wb") as f:
        f.write(data)
    return {"ok": True, "hash": _sha256(data)}
