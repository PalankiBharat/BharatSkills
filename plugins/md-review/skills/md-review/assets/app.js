// app.js — DOM glue. Source of truth: state.md (the full Markdown string).
import { splitBlocks, replaceBlock, toggleTaskLine, taskLineIndices, lineOf } from "/blocks.mjs";

const state = { path: "", md: "", baseHash: "", dirty: false };
let rendering = false; // guards renderDoc against re-entrant calls (blur fired during innerHTML clear)
const $ = (id) => document.getElementById(id);
const renderMd = (s) => (window.marked.parse ? window.marked.parse(s) : window.marked(s));

function setDirty(on) {
  state.dirty = on;
  $("dot").classList.toggle("on", on);
}

function showToast(msg, ok = true) {
  const t = $("toast");
  t.textContent = (ok ? "✓ " : "⚠ ") + msg;
  t.className = "toast show" + (ok ? "" : " warn");
  setTimeout(() => (t.className = "toast"), 2400);
}

function renderDoc() {
  // Clearing #doc can synchronously fire a focused inline textarea's blur handler,
  // which calls renderDoc again. Skip that nested call; the outer loop re-reads
  // state.md after blur returns, leaving exactly one correct render.
  if (rendering) return;
  rendering = true;
  const host = $("doc");
  host.innerHTML = "";
  for (const block of splitBlocks(state.md)) host.appendChild(renderBlock(block));
  rendering = false;
}

function renderBlock(block) {
  const el = document.createElement("div");
  el.className = "block";
  el.innerHTML = renderMd(block.src);
  wireCheckboxes(el, block);
  el.addEventListener("click", (e) => {
    if (e.target.closest("a, input, textarea")) return;
    startInlineEdit(el, block);
  });
  return el;
}

function wireCheckboxes(el, block) {
  const boxes = el.querySelectorAll('input[type="checkbox"]');
  const taskRel = taskLineIndices(block.src);
  const blockLine = lineOf(state.md, block.start);
  boxes.forEach((box, i) => {
    box.disabled = false;
    box.addEventListener("click", (e) => {
      e.stopPropagation();
      state.md = toggleTaskLine(state.md, blockLine + taskRel[i]);
      setDirty(true);
      renderDoc();
    });
  });
}

function startInlineEdit(el, block) {
  const ta = document.createElement("textarea");
  ta.className = "inline";
  ta.value = block.src;
  el.replaceWith(ta);
  ta.style.height = Math.max(48, ta.scrollHeight + 4) + "px";
  ta.focus();
  ta.addEventListener("blur", () => {
    if (ta.value !== block.src) {
      state.md = replaceBlock(state.md, block, ta.value);
      setDirty(true);
    }
    renderDoc();
  });
}

function onRawInput() {
  state.md = $("rawbox").value;
  setDirty(true);
}

function setRaw(on) {
  $("tab-rendered").classList.toggle("active", !on);
  $("tab-raw").classList.toggle("active", on);
  const box = $("rawbox");
  if (on) {
    box.value = state.md;
    box.hidden = false;
    $("doc").hidden = true;
    box.addEventListener("input", onRawInput);
  } else {
    box.removeEventListener("input", onRawInput);
    box.hidden = true;
    $("doc").hidden = false;
    renderDoc();
  }
}

async function save(force = false) {
  $("doc").querySelector("textarea.inline")?.blur(); // flush an open inline edit into state.md first
  const res = await fetch("/api/save", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ markdown: state.md, baseHash: state.baseHash, force }),
  });
  if (res.status === 409) {
    if (confirm("This file changed on disk since you opened it. Overwrite with your version?")) {
      return save(true);
    }
    showToast("Save cancelled — file unchanged", false);
    return;
  }
  if (!res.ok) {
    showToast("Save failed", false);
    return;
  }
  const body = await res.json();
  state.baseHash = body.hash;
  setDirty(false);
  showToast("Saved " + state.path.split("/").pop());
}

async function load() {
  const doc = await (await fetch("/api/doc")).json();
  state.path = doc.path;
  state.md = doc.markdown;
  state.baseHash = doc.hash;
  const name = doc.path.split("/").pop();
  $("fname").textContent = name;
  document.title = "md-review — " + name;
  renderDoc();
}

$("saveBtn").addEventListener("click", () => save());
$("tab-rendered").addEventListener("click", () => setRaw(false));
$("tab-raw").addEventListener("click", () => setRaw(true));
document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "s") { e.preventDefault(); save(); }
});
window.addEventListener("beforeunload", (e) => {
  if (state.dirty) { e.preventDefault(); e.returnValue = ""; }
});

load();
