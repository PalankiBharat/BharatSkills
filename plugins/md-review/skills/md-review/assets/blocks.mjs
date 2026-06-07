// plugins/md-review/skills/md-review/assets/blocks.mjs
// Pure Markdown block model. No DOM. The full Markdown string is the source of truth.
// Assumes LF ("\n") line endings (the repo's Markdown convention).

const FENCE = /^[ \t]*(`{3,}|~{3,})/;

// Split into top-level blocks (separated by blank lines), each carrying its exact
// char offsets so untouched bytes can always be reconstructed.
export function splitBlocks(md) {
  const blocks = [];
  let pos = 0, blockStart = -1, blockEnd = -1, inFence = false;
  const n = md.length;
  while (pos <= n) {
    let nl = md.indexOf("\n", pos);
    if (nl === -1) nl = n;
    const line = md.slice(pos, nl);
    if (FENCE.test(line)) inFence = !inFence;
    const blank = !inFence && line.trim() === "";
    if (blank) {
      if (blockStart >= 0) {
        blocks.push({ start: blockStart, end: blockEnd, src: md.slice(blockStart, blockEnd) });
        blockStart = -1;
      }
    } else {
      if (blockStart < 0) blockStart = pos;
      // end at the newline (exclusive): src omits the trailing \n, which
      // md.slice(block.end) preserves. Do NOT "fix" this to nl + 1.
      blockEnd = nl;
    }
    if (nl === n) break;
    pos = nl + 1;
  }
  if (blockStart >= 0)
    blocks.push({ start: blockStart, end: blockEnd, src: md.slice(blockStart, blockEnd) });
  return blocks;
}

// Splice a block's span with new source — bytes before/after are untouched.
export function replaceBlock(md, block, newSrc) {
  return md.slice(0, block.start) + newSrc + md.slice(block.end);
}

// Flip the checkbox on one source line; every other byte is identical.
export function toggleTaskLine(md, lineIndex) {
  const lines = md.split("\n");
  if (lineIndex < 0 || lineIndex >= lines.length) return md;
  const m = lines[lineIndex].match(/^(\s*[-*+]\s+\[)([ xX])(\].*)$/);
  if (!m) return md;
  lines[lineIndex] = m[1] + (m[2] === " " ? "x" : " ") + m[3];
  return lines.join("\n");
}

// Relative line indices (within `src`) that are task-list items.
export function taskLineIndices(src) {
  const out = [];
  src.split("\n").forEach((line, i) => {
    if (/^\s*[-*+]\s+\[[ xX]\]/.test(line)) out.push(i);
  });
  return out;
}

// Count newlines before a char offset → the line index that offset sits on.
export function lineOf(md, charOffset) {
  let count = 0;
  const stop = Math.min(charOffset, md.length);
  for (let i = 0; i < stop; i++) if (md[i] === "\n") count++;
  return count;
}
