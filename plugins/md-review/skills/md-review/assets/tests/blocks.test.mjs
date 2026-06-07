// plugins/md-review/skills/md-review/assets/tests/blocks.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  splitBlocks, replaceBlock, toggleTaskLine, taskLineIndices, lineOf,
} from "../blocks.mjs";

test("splitBlocks: slices match source, separators are whitespace", () => {
  const md = "# Title\n\nA paragraph.\n\n- [ ] task\n";
  const blocks = splitBlocks(md);
  assert.equal(blocks.length, 3);
  for (const b of blocks) assert.equal(md.slice(b.start, b.end), b.src);
  for (let i = 1; i < blocks.length; i++)
    assert.match(md.slice(blocks[i - 1].end, blocks[i].start), /^\s*$/);
});

test("splitBlocks: fenced code with blank lines stays one block", () => {
  const md = "```\nline1\n\nline2\n```";
  const blocks = splitBlocks(md);
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].src, md);
});

test("replaceBlock: preserves bytes outside the block", () => {
  const md = "# Title\n\nold body\n";
  const block = splitBlocks(md)[1];
  assert.equal(replaceBlock(md, block, "new body"), "# Title\n\nnew body\n");
});

test("toggleTaskLine: flips exactly one character", () => {
  const md = "- [ ] a\n- [x] b\n";
  const out = toggleTaskLine(md, 0);
  assert.equal(out, "- [x] a\n- [x] b\n");
  assert.equal(out.length, md.length);
  let diffs = 0;
  for (let i = 0; i < md.length; i++) if (md[i] !== out[i]) diffs++;
  assert.equal(diffs, 1);
});

test("toggleTaskLine: unchecks and is a no-op on non-task lines", () => {
  assert.equal(toggleTaskLine("- [x] a\n", 0), "- [ ] a\n");
  assert.equal(toggleTaskLine("plain\n", 0), "plain\n");
});

test("taskLineIndices: relative indices of task lines", () => {
  assert.deepEqual(taskLineIndices("intro\n- [ ] one\n- [x] two"), [1, 2]);
});

test("lineOf: counts newlines before an offset", () => {
  const md = "a\nb\nc";
  assert.equal(lineOf(md, 0), 0);
  assert.equal(lineOf(md, 2), 1);
  assert.equal(lineOf(md, 4), 2);
});

test("splitBlocks: fence with 4+ backticks stays one block", () => {
  const md = "````\na\n\nb\n````";
  const blocks = splitBlocks(md);
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].src, md);
});

test("splitBlocks: empty doc → [] and no-trailing-newline → one block", () => {
  assert.deepEqual(splitBlocks(""), []);
  const one = splitBlocks("no trailing newline");
  assert.equal(one.length, 1);
  assert.equal(one[0].src, "no trailing newline");
});

test("replaceBlock: replacing a block with its own src is identity", () => {
  const md = "# A\n\nbody one\n\n- [ ] t\n";
  for (const b of splitBlocks(md)) assert.equal(replaceBlock(md, b, b.src), md);
});
