#!/usr/bin/env node
/**
 * analyze-dimensions.js
 *
 * Walk a screen.json and decide which dp values deserve a named val in a
 * per-feature Dimensions.kt vs which should stay inline at the call site.
 *
 * The rule, in one sentence: emit a named val ONLY for dp values used in two
 * or more places across the screen; one-offs stay inline regardless of
 * context. Anything under the threshold pollutes Dimensions.kt with
 * single-use constants that make the file harder to read than the inline
 * value would have been.
 *
 * When a value does qualify for extraction, we prefer a name that comes from
 * the design itself — in descending order of preference:
 *   1. Figma variable name if this value is bound to a design-token variable
 *      (surfaced as styleRef.<variable-name> in compact screen.json output).
 *   2. Semantic inference from the node name + field: a frame literally
 *      named "PrimaryButton" with a height of 52 → PrimaryButtonHeight.
 *   3. A generic role-based name: Gap16, Padding24, CornerRadius12.
 *
 * Usage:
 *   node analyze-dimensions.js <path-to-screen.json> [options]
 *
 * Options:
 *   --out <dir>       Output directory (default: same dir as screen.json)
 *   --package <pkg>   Kotlin package (default: com.example.ui)
 *   --threshold <n>   Minimum usage count for extraction (default: 2)
 *   --json-out        Emit machine-readable JSON to stdout (no file write)
 *   --help            Show this message
 *
 * Output:
 *   Dimensions.kt     — only if at least one dp value meets the threshold.
 *                       No empty stub file is ever written.
 *   dimensions.json   — every dp value and its decision (extracted / inline),
 *                       so the code generator knows which values to reference
 *                       vs hard-code. Written alongside Dimensions.kt.
 */

'use strict';

const fs = require('fs');
const path = require('path');

// ============================================================================
// CLI
// ============================================================================

function parseArgs(argv) {
  const args = { positional: [] };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--help' || a === '-h') args.help = true;
    else if (a === '--json-out') args.jsonOut = true;
    else if (a.startsWith('--')) args[a.slice(2)] = argv[++i];
    else args.positional.push(a);
  }
  return args;
}

function usage() {
  console.log(`Usage: node analyze-dimensions.js <screen.json> [options]

Options:
  --out <dir>       Output directory (default: same dir as screen.json)
  --package <pkg>   Kotlin package (default: com.example.ui)
  --threshold <n>   Minimum usage count for extraction (default: 2)
  --json-out        Emit machine-readable JSON to stdout (no file write)
  --help            Show this message
`);
}

// ============================================================================
// Dimension collection
// ============================================================================

/**
 * Walk the screen tree and count every dp usage. Each usage is a
 * { value, field, nodeName, variableName? } tuple; we accumulate them
 * keyed by integer dp value.
 *
 * Fields considered:
 *   - layout.padding (scalar, {v,h} pair, or {t,r,b,l})
 *   - layout.gap
 *   - radius
 *   - stroke.weight
 *   - explicit box widths and heights BUT only when the node is a leaf
 *     component (TEXT, INSTANCE, or an asset) — walking every container
 *     box would produce noise since containers are usually sized by their
 *     children.
 */
function collectDimensions(node, usages, opts, parentName) {
  if (!node) return;
  const name = node.name || parentName || '';

  function add(field, value, nameHint) {
    if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) return;
    // Round to whole dp — design tools often surface 15.99 or 16.01 due to
    // math. We collapse to the nearest whole dp for counting purposes;
    // fractional values get their own bucket only when genuinely distinct.
    const key = Math.round(value * 100) / 100;
    if (!usages[key]) usages[key] = [];
    usages[key].push({
      field, nodeName: name, nameHint: nameHint || null,
      variableName: extractVariableHint(node, field),
    });
  }

  // Padding — can be scalar, {v,h}, or {t,r,b,l}
  if (node.layout && node.layout.padding != null) {
    const p = node.layout.padding;
    if (typeof p === 'number') {
      add('padding', p);
    } else if (typeof p === 'object') {
      if (p.v != null) add('paddingV', p.v);
      if (p.h != null) add('paddingH', p.h);
      if (p.t != null) add('paddingT', p.t);
      if (p.r != null) add('paddingR', p.r);
      if (p.b != null) add('paddingB', p.b);
      if (p.l != null) add('paddingL', p.l);
    }
  }
  if (node.layout && node.layout.gap) add('gap', node.layout.gap);
  if (node.radius) add('radius', node.radius);
  if (node.stroke && node.stroke.weight) add('strokeWidth', node.stroke.weight);

  // Explicit size — only for leaves. Containers derive their size from
  // contents; capturing every container width/height floods the usage
  // counts with values that aren't really "dimensions" in the design sense.
  const isLeaf = node.type === 'TEXT' || node.type === 'INSTANCE' || node.asset;
  if (isLeaf && node.box) {
    if (node.box.w) add('width', node.box.w);
    if (node.box.h) add('height', node.box.h);
  }

  if (Array.isArray(node.children)) {
    for (const c of node.children) collectDimensions(c, usages, opts, name);
  }
}

/**
 * If the node's styleRef contains a spacing/sizing variable name,
 * surface it. Figma's boundVariables are a much higher-quality naming
 * signal than anything we could derive from node names.
 *
 * NOTE: figma-to-json.js currently surfaces colour/text style variables
 * via styleRef; if the user's designs bind spacing variables, those would
 * appear here too. The accessor is intentionally defensive so it works
 * today and gets better when that plumbing extends.
 */
function extractVariableHint(node, field) {
  if (!node.styleRef) return null;
  // Heuristic: if the field name matches a styleRef key, assume it's the
  // variable binding (e.g. styleRef.gap, styleRef.radius, styleRef.padding).
  return node.styleRef[field] || null;
}

// ============================================================================
// Decision logic
// ============================================================================

/**
 * Given the collected usages, decide for each dp value whether it deserves
 * extraction. Returns:
 *   {
 *     extracted: [{ value, name, usages, reason, kotlinName }],
 *     inline:    [{ value, usages }],  // below threshold
 *   }
 */
function decide(usages, opts = {}) {
  const threshold = opts.threshold != null ? opts.threshold : 2;
  const extracted = [];
  const inline = [];
  const usedNames = new Set();

  // Sort by (usage count desc, value asc) so the most-used dimensions get
  // first pick at the best names and the output file is stable across runs.
  const entries = Object.keys(usages)
    .map(k => ({ value: Number(k), usages: usages[k] }))
    .sort((a, b) => b.usages.length - a.usages.length || a.value - b.value);

  for (const entry of entries) {
    if (entry.usages.length < threshold) {
      inline.push(entry);
      continue;
    }
    const decision = chooseName(entry, usedNames);
    usedNames.add(decision.name);
    extracted.push({ ...entry, ...decision });
  }

  return { extracted, inline };
}

/**
 * Pick the best name for an extracted dimension. Tiers:
 *   1. Figma variable binding (styleRef value that looks like a var name)
 *   2. Semantic inference from node context — if all usages come from nodes
 *      whose names share a common prefix (e.g., every usage is on a node
 *      named "PrimaryButton*"), that prefix becomes part of the name.
 *   3. Generic role-based name: Gap16, Padding24, etc.
 */
function chooseName(entry, usedNames) {
  const { value, usages } = entry;
  const dpLabel = Number.isInteger(value) ? String(value) : String(value).replace('.', '_');

  // Tier 1: Figma variable name on any usage
  for (const u of usages) {
    if (u.variableName) {
      const name = toPascal(u.variableName);
      if (name && !usedNames.has(name)) {
        return { name, kotlinName: name, reason: 'variable' };
      }
    }
  }

  // Tier 2: common semantic prefix from node names
  const prefix = commonNodePrefix(usages.map(u => u.nodeName));
  const fieldRole = dominantField(usages.map(u => u.field));
  if (prefix && fieldRole) {
    const candidate = `${toPascal(prefix)}${toPascal(fieldRole)}`;
    if (!usedNames.has(candidate)) {
      return { name: candidate, kotlinName: candidate, reason: 'semantic' };
    }
  }

  // Tier 3: generic role-based fallback
  const generic = `${toPascal(fieldRole || 'Size')}${dpLabel}`;
  let candidate = generic;
  let suffix = 2;
  while (usedNames.has(candidate)) {
    candidate = `${generic}_${suffix++}`;
  }
  return { name: candidate, kotlinName: candidate, reason: 'generic' };
}

/**
 * Find the longest common meaningful prefix across node names.
 * "PrimaryButton/Background" + "PrimaryButton/Label" → "PrimaryButton".
 * "Header" + "Footer" → "" (nothing in common).
 * Ignores empty / "Frame N" / "Group N" default names.
 */
function commonNodePrefix(names) {
  const meaningful = names.filter(n =>
    n && !/^(frame|group|rectangle|vector|ellipse)\s*\d*$/i.test(n));
  if (meaningful.length < 2) return null;

  // Normalise: split on non-alphanumeric into tokens, compare token-wise.
  const tokenLists = meaningful.map(n =>
    n.split(/[^A-Za-z0-9]+/).filter(Boolean));
  const minLen = Math.min(...tokenLists.map(l => l.length));
  const common = [];
  for (let i = 0; i < minLen; i++) {
    const first = tokenLists[0][i].toLowerCase();
    if (tokenLists.every(l => l[i].toLowerCase() === first)) {
      common.push(tokenLists[0][i]);
    } else break;
  }
  if (!common.length) return null;
  return common.join('');
}

/**
 * Pick the most common field amongst usages — that tells us the role.
 * 3 paddings + 1 gap → 'padding'.
 * All heights → 'height'.
 * Mixed (1 width + 1 height + 1 padding) → null, because the value isn't
 * really a "height" or a "padding" — it's just a common number.
 */
function dominantField(fields) {
  // First, collapse all padding variants into a single 'padding' label so
  // mixed uses like (padding scalar + paddingH) still count as padding.
  const normalised = fields.map(f => /^padding/.test(f) ? 'padding' : f);
  const counts = {};
  for (const f of normalised) counts[f] = (counts[f] || 0) + 1;
  const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1]);
  if (!sorted.length) return null;
  const [top, topCount] = sorted[0];
  // Require at least 60% of usages in the dominant field to claim a role.
  if (topCount / normalised.length < 0.6) return null;
  if (top === 'padding') return 'Padding';
  if (top === 'gap') return 'Gap';
  if (top === 'radius') return 'CornerRadius';
  if (top === 'strokeWidth') return 'StrokeWidth';
  if (top === 'width' || top === 'height') return top.charAt(0).toUpperCase() + top.slice(1);
  return toPascal(top);
}

function toPascal(s) {
  if (!s) return '';
  return String(s)
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map(w => w[0].toUpperCase() + w.slice(1))
    .join('');
}

// ============================================================================
// Kotlin emission
// ============================================================================

function emitDimensionsKt(extracted, pkg) {
  if (!extracted.length) return null; // don't write an empty file
  const lines = [
    `package ${pkg}`,
    '',
    'import androidx.compose.ui.unit.dp',
    '',
    '// Dimensions extracted from the Figma design. Only values used in two',
    '// or more places appear here; one-off dp values stay inline at their',
    '// call sites to keep this file readable.',
    '',
  ];
  for (const d of extracted) {
    const where = d.usages.length === 1
      ? `used once`
      : `used ${d.usages.length}× (${distinctFields(d.usages)})`;
    const why = d.reason === 'variable'
      ? 'from Figma variable'
      : d.reason === 'semantic' ? 'derived from node names' : 'generic name';
    lines.push(`// ${where}, ${why}`);
    lines.push(`val ${d.kotlinName} = ${formatDp(d.value)}`);
    lines.push('');
  }
  return lines.join('\n');
}

function distinctFields(usages) {
  const set = new Set(usages.map(u => u.field));
  return [...set].join(', ');
}

function formatDp(v) {
  // Whole numbers: `16.dp`. Fractional: `15.5.dp`.
  if (Number.isInteger(v)) return `${v}.dp`;
  return `${v}.dp`;
}

// ============================================================================
// Main
// ============================================================================

function main() {
  const args = parseArgs(process.argv);
  if (args.help || !args.positional[0]) {
    usage();
    process.exit(args.help ? 0 : 1);
  }

  const inputPath = args.positional[0];
  let screenJson;
  try {
    screenJson = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  } catch (e) {
    console.error(`Could not read ${inputPath}: ${e.message}`);
    process.exit(1);
  }
  const root = screenJson.layout || screenJson;
  if (!root) {
    console.error('screen.json has no layout root');
    process.exit(1);
  }

  const usages = {};
  collectDimensions(root, usages, { threshold: Number(args.threshold) || 2 });
  const result = decide(usages, { threshold: Number(args.threshold) || 2 });

  if (args.jsonOut) {
    console.log(JSON.stringify({
      extracted: result.extracted.map(e => ({
        value: e.value, name: e.kotlinName, usages: e.usages.length,
        fields: distinctFields(e.usages), reason: e.reason,
      })),
      inline: result.inline.map(e => ({ value: e.value, usages: e.usages.length })),
    }, null, 2));
    return;
  }

  const outDir = args.out || path.dirname(inputPath);
  const pkg = args.package || 'com.example.ui';
  const kotlin = emitDimensionsKt(result.extracted, pkg);

  // Decision artifact — the code generator uses this to know which values
  // to reference by name and which to write inline.
  const decisionJson = {
    generatedAt: new Date().toISOString(),
    threshold: Number(args.threshold) || 2,
    extracted: Object.fromEntries(
      result.extracted.map(e => [String(e.value), {
        name: e.kotlinName, usages: e.usages.length,
        fields: distinctFields(e.usages), reason: e.reason,
      }])
    ),
    inline: result.inline.map(e => e.value),
  };

  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, 'dimensions.json'), JSON.stringify(decisionJson, null, 2));

  if (kotlin) {
    fs.writeFileSync(path.join(outDir, 'Dimensions.kt'), kotlin);
    console.log(`Extracted ${result.extracted.length} reused dimension(s), ${result.inline.length} one-off(s) stay inline`);
    console.log(`  -> ${path.resolve(outDir, 'Dimensions.kt')}`);
    console.log(`  -> ${path.resolve(outDir, 'dimensions.json')}`);
  } else {
    console.log(`No dimensions qualified for extraction (all ${result.inline.length} value(s) are one-offs).`);
    console.log(`Dimensions.kt not written. Inline decision map:`);
    console.log(`  -> ${path.resolve(outDir, 'dimensions.json')}`);
  }
}

if (require.main === module) {
  try { main(); }
  catch (e) { console.error('ERROR:', e.message); process.exit(1); }
}

module.exports = {
  collectDimensions,
  decide,
  chooseName,
  commonNodePrefix,
  dominantField,
  emitDimensionsKt,
  toPascal,
};
