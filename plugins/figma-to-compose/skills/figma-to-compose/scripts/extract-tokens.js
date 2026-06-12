#!/usr/bin/env node
/**
 * extract-tokens.js
 *
 * Read a screen.json produced by figma-to-json.js and emit Kotlin files
 * containing the design tokens used in the design:
 *   - Color.kt      : one `val` per unique fill (and stroke) colour
 *   - Typography.kt : one `val TextStyle` per unique {font, size, weight, …} combo
 *
 * These files are drop-in for a Jetpack Compose project. You can either use
 * them directly (`import com.example.ui.theme.*`) or fold them into an
 * existing Material3 `ColorScheme` / `Typography`.
 *
 * Usage:
 *   node extract-tokens.js <path-to-screen.json> [--out <dir>] [--package <pkg>]
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
    else if (a.startsWith('--')) args[a.slice(2)] = argv[++i];
    else args.positional.push(a);
  }
  return args;
}

function usage() {
  console.log(`Usage: node extract-tokens.js <screen.json> [options]

Options:
  --out <dir>             Output directory (default: ./kotlin-out)
  --package <pkg>         Kotlin package (default: com.example.ui.theme)
  --match-existing <p>    Path to existing Kotlin tokens. Can be a directory
                          (scanned recursively for *.kt files) or a single file.
                          When a Figma style name or hex matches an existing
                          token, that token is reused instead of a new one
                          being emitted. Writes figma-token-reuse.json to
                          the output directory recording every match.
  --help                  Show this message
`);
}

// ============================================================================
// Colour parsing (accepts both rgba() strings and #RRGGBB[AA] hex)
// ============================================================================

/**
 * Parse a colour string from screen.json — either rgba() (legacy verbose)
 * or hex (#RRGGBB / #RRGGBBAA, compact default). Returns {r, g, b, a} as
 * 0–255 / 0–1 values.
 */
function parseRgba(s) {
  if (typeof s !== 'string') return null;

  // Hex: #RRGGBB or #RRGGBBAA (new compact format)
  let m = /^#([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(s.trim());
  if (m) {
    const hex = m[1];
    return {
      r: parseInt(hex.slice(0, 2), 16),
      g: parseInt(hex.slice(2, 4), 16),
      b: parseInt(hex.slice(4, 6), 16),
      a: m[2] ? parseInt(m[2], 16) / 255 : 1,
    };
  }

  // rgba()
  m = s.match(/rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)/);
  if (!m) return null;
  return {

    r: Number(m[1]),
    g: Number(m[2]),
    b: Number(m[3]),
    a: m[4] === undefined ? 1 : Number(m[4]),
  };
}

/**
 * Compose Color literal: `Color(0xAARRGGBB)`.
 */
function toComposeColor({ r, g, b, a }) {
  const aa = Math.round(a * 255);
  const hex = [aa, r, g, b]
    .map(n => n.toString(16).toUpperCase().padStart(2, '0'))
    .join('');
  return `Color(0x${hex})`;
}

/**
 * Human-readable name for a colour, derived from the fields it's used in.
 * Falls back to Color{index} if nothing descriptive is available.
 */
function colorNameFromUsage(usage, rgba, fallbackIndex) {
  // Prefer names like "headerBackground" drawn from node name + field.
  const hints = new Set();
  for (const u of usage) {
    if (u.nodeName) {
      hints.add(`${camelCaseFromName(u.nodeName)}${capitalize(u.field)}`);
    }
  }
  if (hints.size === 1) {
    return [...hints][0];
  }
  // Multiple unrelated uses → derive a name from the colour itself.
  return describeColour(rgba) || `color${fallbackIndex}`;
}

function describeColour({ r, g, b, a }) {
  if (a === 0) return 'transparent';
  if (r === g && g === b) {
    if (r === 0) return 'black';
    if (r === 255) return 'white';
    return `gray${r}`;
  }
  // Hue-ish label + 6-digit hex for uniqueness.
  const hex = [r, g, b].map(n => n.toString(16).padStart(2, '0')).join('').toUpperCase();
  const hue = hueLabel(r, g, b);
  return `${hue}${hex}`;
}

function hueLabel(r, g, b) {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  if (max - min < 15) return 'neutral';
  if (r === max && g >= b) return g > 200 && b < 100 ? 'yellow' : 'red';
  if (r === max) return b > 100 ? 'pink' : 'orange';
  if (g === max) return b > r ? 'teal' : 'green';
  // b === max
  return r > g ? 'purple' : 'blue';
}

// ============================================================================
// Typography handling
// ============================================================================

// Figma `fontWeight` (numeric) → Compose FontWeight constant.
const WEIGHT_MAP = {
  100: 'FontWeight.Thin',
  200: 'FontWeight.ExtraLight',
  300: 'FontWeight.Light',
  400: 'FontWeight.Normal',
  500: 'FontWeight.Medium',
  600: 'FontWeight.SemiBold',
  700: 'FontWeight.Bold',
  800: 'FontWeight.ExtraBold',
  900: 'FontWeight.Black',
};

// Figma `textAlignHorizontal` → Compose TextAlign constant.
const ALIGN_MAP = {
  LEFT: 'TextAlign.Start',
  CENTER: 'TextAlign.Center',
  RIGHT: 'TextAlign.End',
  JUSTIFIED: 'TextAlign.Justify',
};

function weightToCompose(w) {
  if (w == null) return null;
  // Figma sometimes stores weights as exact matches, sometimes as numbers like 450.
  // Snap to nearest supported weight.
  const supported = Object.keys(WEIGHT_MAP).map(Number);
  const nearest = supported.reduce((best, cur) =>
    Math.abs(cur - w) < Math.abs(best - w) ? cur : best,
  supported[0]);
  return WEIGHT_MAP[nearest];
}

/**
 * Hash a text style for deduplication — two styles with the same (font, size,
 * weight, lineHeight, letterSpacing, align) collapse into one named TextStyle.
 * Colour is deliberately excluded here; colour lives in Color.kt.
 */
function textStyleKey(s) {
  return JSON.stringify([
    s.font || '',
    s.size || 0,
    s.weight || 400,
    s.lineHeight || 0,
    s.letterSpacing || 0,
    s.align || '',
  ]);
}

function textStyleName(s, index) {
  const font = (s.font || 'Text').replace(/[^A-Za-z0-9]/g, '');
  const size = Math.round(s.size || 0);
  const wname = s.weight ? (WEIGHT_MAP[s.weight] || 'FontWeight.Normal')
    .replace('FontWeight.', '') : 'Normal';
  if (!size) return `TextStyle${index}`;
  return `${lowerFirst(font)}${size}${wname}`;
}

// ============================================================================
// Existing-token scanner — read the user's repo to find tokens we should reuse
// ============================================================================

/**
 * Normalise a token name to make name-equality matches robust to casing and
 * punctuation style. 'Primary', 'primary', 'primaryColor' all collapse to
 * 'primary'. 'surface-strong', 'surface_strong', 'SurfaceStrong' all collapse
 * to 'surfacestrong'.
 */
function normaliseName(name) {
  if (!name) return '';
  return String(name)
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')         // camelCase → snake_case
    .replace(/([A-Z])([A-Z][a-z])/g, '$1_$2')       // ACRONYMBoundary
    .toLowerCase()
    .replace(/color$|fill$|stroke$|text$/i, '')     // strip trailing role suffix
    .replace(/[^a-z0-9]/g, '');
}

/**
 * Parse a single Kotlin file for token declarations. Extracts:
 *   - `val X = Color(0xAARRGGBB)` → colour tokens
 *   - `val X = TextStyle(...)` with recognisable fields → text-style tokens
 *
 * Returns { colors: [{name, hex}], textStyles: [{name, font, size, weight}] }.
 * Intentionally narrow — we don't try to parse arbitrary Kotlin, only the
 * shapes that `extract-tokens.js` itself produces, which is what a
 * design-system `Color.kt` or `Typography.kt` actually looks like.
 */
function parseKotlinTokens(source) {
  const colors = [];
  const textStyles = [];

  // val NAME = Color(0xAARRGGBB)  — capturing 8-hex-digit form
  const colorRe = /\bval\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*Color\s*\(\s*0x([0-9A-Fa-f]{8})\s*\)/g;
  let m;
  while ((m = colorRe.exec(source)) !== null) {
    const aarrggbb = m[2].toUpperCase();
    // Normalise to #RRGGBB or #RRGGBBAA so it matches what screen.json emits.
    const aa = aarrggbb.slice(0, 2);
    const rrggbb = aarrggbb.slice(2);
    const hex = aa === 'FF' ? `#${rrggbb}` : `#${rrggbb}${aa}`;
    colors.push({ name: m[1], hex });
  }

  // Also accept 6-hex-digit form `Color(0xRRGGBB)` — compiles as fully opaque
  // in Kotlin; older codebases sometimes write it this way.
  const color6Re = /\bval\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*Color\s*\(\s*0x([0-9A-Fa-f]{6})\s*\)/g;
  while ((m = color6Re.exec(source)) !== null) {
    colors.push({ name: m[1], hex: `#${m[2].toUpperCase()}` });
  }

  // val NAME = TextStyle(...)  — we only surface font / size / weight
  // because those are the dimensions screen.json actually captures. Parsing
  // the block itself is fragile; use a tolerant match.
  const textStyleRe = /\bval\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*TextStyle\s*\(([\s\S]*?)\)/g;
  while ((m = textStyleRe.exec(source)) !== null) {
    const name = m[1];
    const body = m[2];
    const sizeMatch = /fontSize\s*=\s*(\d+(?:\.\d+)?)\.sp/.exec(body);
    const weightMatch = /fontWeight\s*=\s*FontWeight\.([A-Za-z]+)/.exec(body);
    const fontMatch = /fontFamily\s*=\s*([A-Za-z_][A-Za-z0-9_]*)/.exec(body);
    const weightNumMap = {
      Thin: 100, ExtraLight: 200, Light: 300, Normal: 400,
      Medium: 500, SemiBold: 600, Bold: 700, ExtraBold: 800, Black: 900,
    };
    textStyles.push({
      name,
      font: fontMatch ? fontMatch[1] : null,
      size: sizeMatch ? Number(sizeMatch[1]) : null,
      weight: weightMatch ? weightNumMap[weightMatch[1]] || 400 : 400,
    });
  }

  return { colors, textStyles };
}

/**
 * Scan --match-existing input. Accepts a directory (walks .kt recursively)
 * or a single file. Returns the aggregated parse result plus source file
 * paths for attribution.
 */
function scanExistingTokens(inputPath) {
  const out = { colors: [], textStyles: [], filesScanned: [] };
  if (!inputPath) return out;
  const stat = fs.statSync(inputPath);
  const files = [];
  if (stat.isFile()) {
    files.push(inputPath);
  } else if (stat.isDirectory()) {
    // Recursive walk for .kt files. Skip build/ / generated/ / .gradle/
    // which are where generated code lives and would produce false matches.
    function walkDir(d) {
      for (const entry of fs.readdirSync(d)) {
        if (entry === 'build' || entry === '.gradle' || entry === 'generated'
            || entry === 'node_modules' || entry.startsWith('.')) continue;
        const full = path.join(d, entry);
        const s = fs.statSync(full);
        if (s.isDirectory()) walkDir(full);
        else if (entry.endsWith('.kt')) files.push(full);
      }
    }
    walkDir(inputPath);
  }

  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    const parsed = parseKotlinTokens(src);
    if (parsed.colors.length || parsed.textStyles.length) {
      out.colors.push(...parsed.colors.map(c => ({ ...c, file: f })));
      out.textStyles.push(...parsed.textStyles.map(t => ({ ...t, file: f })));
      out.filesScanned.push(f);
    }
  }
  return out;
}

/**
 * Build lookup maps for the three matching tiers:
 *   - byName: { normalisedName → {name, hex, file} }   → tier 1 (exact name)
 *   - byHex:  { normalisedHex → {name, hex, file}[] }  → tier 2 (exact hex)
 * Tier 3 (near-match) is intentionally absent — per user spec, we want exact
 * findings only.
 */
function buildExistingTokenMaps(existing) {
  const byName = {};
  const byHex = {};
  for (const c of existing.colors) {
    byName[normaliseName(c.name)] = c;
    const hexKey = c.hex.toUpperCase();
    if (!byHex[hexKey]) byHex[hexKey] = [];
    byHex[hexKey].push(c);
  }
  const textByName = {};
  const textBySig = {};
  for (const t of existing.textStyles) {
    textByName[normaliseName(t.name)] = t;
    // Index under the normal sig AND under a "font-less" sig. Existing
    // Kotlin TextStyle vals often omit fontFamily (it gets applied later via
    // a theme wrapper), while Figma always supplies the font. A size+weight
    // match is a legitimate signal that the two are the same style.
    const fullSig = `${t.font || ''}|${t.size || 0}|${t.weight || 400}`;
    const fontlessSig = `|${t.size || 0}|${t.weight || 400}`;
    for (const sig of new Set([fullSig, fontlessSig])) {
      if (!textBySig[sig]) textBySig[sig] = [];
      textBySig[sig].push(t);
    }
  }
  return { colors: { byName, byHex }, textStyles: { byName: textByName, bySig: textBySig } };
}

// ============================================================================
// Tree walkers
// ============================================================================

function walk(node, cb) {
  if (!node) return;
  cb(node);
  if (Array.isArray(node.children)) {
    for (const c of node.children) walk(c, cb);
  }
}

/**
 * Pull all unique colours from fills, strokes, and text colours in the tree.
 * Records the design-system style name (from figma-to-json's `styleRef`
 * annotation) for each usage — this is the tier-1 match signal.
 */
function collectColors(root) {
  const map = new Map(); // key: "r,g,b,a" → { rgba, usage: [{nodeName, field, styleRefName}] }
  function add(nodeName, field, value, styleRefName) {
    const rgba = parseRgba(value);
    if (!rgba) return;
    const key = `${rgba.r},${rgba.g},${rgba.b},${rgba.a}`;
    if (!map.has(key)) map.set(key, { rgba, usage: [] });
    map.get(key).usage.push({ nodeName, field, styleRefName: styleRefName || null });
  }
  walk(root, n => {
    const refs = n.styleRef || {};
    if (n.fill) add(n.name, 'fill', n.fill, refs.fill);
    if (n.text && n.text.color) add(n.name, 'textColor', n.text.color, refs.fill);
    if (n.stroke && n.stroke.color) add(n.name, 'stroke', n.stroke.color, refs.stroke);
    if (n.effects) {
      for (const e of n.effects) {
        if (e.color) add(n.name, 'shadow', e.color, refs.effect);
      }
    }
  });
  return map;
}

function collectTextStyles(root, topLevelTextStyles = {}) {
  const map = new Map(); // key → { style, usage: [{nodeName, styleRefName}] }
  walk(root, n => {
    if (n.type !== 'TEXT' || !n.text) return;
    // screen.json may store the style either inline (legacy verbose) or as a
    // key into the top-level `textStyles` registry (compact default).
    const s = n.text.style
      || (n.text.styleKey && topLevelTextStyles[n.text.styleKey])
      || null;
    if (!s) return;
    const key = textStyleKey(s);
    if (!map.has(key)) map.set(key, { style: s, usage: [] });
    const refs = n.styleRef || {};
    map.get(key).usage.push({ nodeName: n.name, styleRefName: refs.text || null });
  });
  return map;
}

// ============================================================================
// Kotlin emission
// ============================================================================

function camelCaseFromName(name) {
  if (!name) return 'unnamed';
  const parts = String(name)
    .replace(/[^A-Za-z0-9]+/g, ' ')
    .trim()
    .split(/\s+/);
  if (!parts.length) return 'unnamed';
  return parts[0].toLowerCase() +
    parts.slice(1).map(w => capitalize(w.toLowerCase())).join('');
}

const capitalize = (s) => s ? s[0].toUpperCase() + s.slice(1) : s;
const lowerFirst = (s) => s ? s[0].toLowerCase() + s.slice(1) : s;

function rgbaToHexKey(rgba) {
  // Produce the #RRGGBB or #RRGGBBAA form that matches parseKotlinTokens output.
  const rr = Math.round(rgba.r).toString(16).padStart(2, '0').toUpperCase();
  const gg = Math.round(rgba.g).toString(16).padStart(2, '0').toUpperCase();
  const bb = Math.round(rgba.b).toString(16).padStart(2, '0').toUpperCase();
  if (rgba.a >= 0.999) return `#${rr}${gg}${bb}`;
  const aa = Math.round(rgba.a * 255).toString(16).padStart(2, '0').toUpperCase();
  return `#${rr}${gg}${bb}${aa}`;
}

/**
 * Emit Color.kt. If `existing` is provided, reuse matching tokens rather
 * than emitting duplicates. The reuse map returned records every decision
 * so verify.js and the code generator can consult it.
 *
 * Returns: { kotlin: string, reuse: { byFigmaKey: {figmaKey, reason, reusedName, file?, newName?, hex} } }
 *
 * reason values: 'name-match' (tier 1), 'hex-match' (tier 2), 'new' (no match)
 */
function emitColorKt(colorMap, pkg, existing = null) {
  const lines = [
    `package ${pkg}`,
    '',
    'import androidx.compose.ui.graphics.Color',
    '',
    '// Colours extracted from the Figma design. One val per unique RGBA value',
    '// that does NOT already exist in the repo. Tokens that matched an',
    '// existing val by design-system name or by hex are listed at the end',
    '// for reference but NOT redeclared here.',
    '',
  ];

  const reuse = {}; // figmaKey → decision record
  const emitted = []; // { name, hex, usage }
  const reused = [];  // { figmaKey, hex, existingName, reason, file }
  const seenNames = new Set();
  let i = 1;

  // Sort by usage count so most-used colours appear first in the output.
  const sorted = [...colorMap.values()].sort(
    (a, b) => b.usage.length - a.usage.length
  );

  for (const entry of sorted) {
    const hexKey = rgbaToHexKey(entry.rgba);
    const figmaKey = hexKey;

    // Tier 1: name match via Figma styleRef
    let styleRefName = null;
    for (const u of entry.usage) {
      if (u.styleRefName) { styleRefName = u.styleRefName; break; }
    }
    if (existing && styleRefName) {
      const normalised = normaliseName(styleRefName);
      const match = existing.colors.byName[normalised];
      if (match) {
        reuse[figmaKey] = {
          figmaKey, hex: hexKey,
          reason: 'name-match',
          figmaStyleName: styleRefName,
          reusedName: match.name,
          file: match.file,
        };
        reused.push({ figmaKey, hex: hexKey, existingName: match.name, reason: 'name-match', file: match.file });
        entry.name = match.name; // annotate for typography cross-reference
        continue;
      }
    }

    // Tier 2: exact hex match
    if (existing) {
      const hexMatches = existing.colors.byHex[hexKey] || [];
      if (hexMatches.length === 1) {
        const match = hexMatches[0];
        reuse[figmaKey] = {
          figmaKey, hex: hexKey,
          reason: 'hex-match',
          reusedName: match.name,
          file: match.file,
        };
        reused.push({ figmaKey, hex: hexKey, existingName: match.name, reason: 'hex-match', file: match.file });
        entry.name = match.name;
        continue;
      }
      if (hexMatches.length > 1) {
        // Multiple existing tokens share this hex — too ambiguous to auto-pick.
        // Emit a new token but record the candidates so the user can manually
        // pick the right one.
        reuse[figmaKey] = {
          figmaKey, hex: hexKey,
          reason: 'ambiguous-hex',
          candidates: hexMatches.map(m => ({ name: m.name, file: m.file })),
        };
      }
    }

    // Tier 3: genuinely new — emit a val
    let name = styleRefName
      ? camelCaseFromName(styleRefName)
      : colorNameFromUsage(entry.usage, entry.rgba, i);
    let unique = name;
    let suffix = 2;
    while (seenNames.has(unique)) unique = `${name}${suffix++}`;
    seenNames.add(unique);
    entry.name = unique;

    const where = entry.usage.length === 1
      ? `used in ${entry.usage[0].nodeName || '?'}`
      : `used ${entry.usage.length}× (e.g. ${(entry.usage[0].nodeName || '?').slice(0, 40)})`;
    const styleNote = styleRefName ? ` [Figma style: ${styleRefName}]` : '';
    lines.push(`// ${where}${styleNote}`);
    if (reuse[figmaKey] && reuse[figmaKey].reason === 'ambiguous-hex') {
      const candidates = reuse[figmaKey].candidates.map(c => c.name).join(', ');
      lines.push(`// NOTE: hex matches multiple existing tokens (${candidates}) — review and replace by hand if needed`);
    }
    lines.push(`val ${unique} = ${toComposeColor(entry.rgba)}`);
    lines.push('');
    emitted.push({ name: unique, hex: hexKey, usage: entry.usage.length });
    reuse[figmaKey] = reuse[figmaKey] || { figmaKey, hex: hexKey, reason: 'new' };
    reuse[figmaKey].newName = unique;
    i++;
  }

  if (reused.length) {
    lines.push('');
    lines.push('// ─── REUSED FROM EXISTING REPO (not redeclared above) ───');
    for (const r of reused) {
      const loc = r.file ? ` (${path.basename(r.file)})` : '';
      lines.push(`// ${r.hex}  →  ${r.existingName}  [${r.reason}]${loc}`);
    }
  }

  return { kotlin: lines.join('\n'), reuse, emitted, reused };
}

function emitTypographyKt(textStyles, colorMap, pkg, existing = null) {
  const lines = [
    `package ${pkg}`,
    '',
    'import androidx.compose.ui.text.TextStyle',
    'import androidx.compose.ui.text.font.FontFamily',
    'import androidx.compose.ui.text.font.FontWeight',
    'import androidx.compose.ui.text.style.TextAlign',
    'import androidx.compose.ui.unit.sp',
    '',
    '// Text styles extracted from the Figma design. Styles that matched an',
    '// existing repo TextStyle by design-system name or by (font, size, weight)',
    '// are not redeclared — see the reuse block at the bottom.',
    '',
  ];

  const reuse = {};
  const emitted = [];
  const reused = [];
  const seenNames = new Set();
  let i = 1;
  const sorted = [...textStyles.values()].sort(
    (a, b) => b.usage.length - a.usage.length
  );

  for (const entry of sorted) {
    const sig = `${entry.style.font || ''}|${entry.style.size || 0}|${entry.style.weight || 400}`;

    // Tier 1: name match from Figma styleRef (text styles track their own refs)
    let styleRefName = null;
    for (const u of entry.usage) {
      if (u.styleRefName) { styleRefName = u.styleRefName; break; }
    }
    if (existing && styleRefName) {
      const normalised = normaliseName(styleRefName);
      const match = existing.textStyles.byName[normalised];
      if (match) {
        reuse[sig] = { sig, reason: 'name-match', figmaStyleName: styleRefName, reusedName: match.name, file: match.file };
        reused.push({ sig, existingName: match.name, reason: 'name-match', file: match.file });
        continue;
      }
    }

    // Tier 2: (font, size, weight) match. Also try font-less fallback because
    // existing repo TextStyle vals often omit fontFamily.
    if (existing) {
      const fontless = `|${entry.style.size || 0}|${entry.style.weight || 400}`;
      const matches = existing.textStyles.bySig[sig]
        || existing.textStyles.bySig[fontless]
        || [];
      if (matches.length === 1) {
        const match = matches[0];
        reuse[sig] = { sig, reason: 'tuple-match', reusedName: match.name, file: match.file };
        reused.push({ sig, existingName: match.name, reason: 'tuple-match', file: match.file });
        continue;
      }
      if (matches.length > 1) {
        reuse[sig] = { sig, reason: 'ambiguous-tuple', candidates: matches.map(m => ({ name: m.name, file: m.file })) };
      }
    }

    // Tier 3: emit new
    let name = styleRefName ? camelCaseFromName(styleRefName) : textStyleName(entry.style, i);
    let unique = name;
    let suffix = 2;
    while (seenNames.has(unique)) unique = `${name}${suffix++}`;
    seenNames.add(unique);

    const where = entry.usage.length === 1
      ? `used in ${entry.usage[0].nodeName || '?'}`
      : `used ${entry.usage.length}×`;
    const styleNote = styleRefName ? ` [Figma style: ${styleRefName}]` : '';
    lines.push(`// ${where}${styleNote}`);
    if (reuse[sig] && reuse[sig].reason === 'ambiguous-tuple') {
      const candidates = reuse[sig].candidates.map(c => c.name).join(', ');
      lines.push(`// NOTE: (font, size, weight) matches multiple existing styles (${candidates}) — review by hand`);
    }
    lines.push(`val ${unique} = TextStyle(`);
    const fields = composeTextStyleFields(entry.style);
    lines.push(fields.map(l => '    ' + l).join(',\n'));
    lines.push(')');
    lines.push('');
    emitted.push({ name: unique, sig });
    reuse[sig] = reuse[sig] || { sig, reason: 'new' };
    reuse[sig].newName = unique;
    i++;
  }

  if (reused.length) {
    lines.push('');
    lines.push('// ─── REUSED FROM EXISTING REPO ───');
    for (const r of reused) {
      const loc = r.file ? ` (${path.basename(r.file)})` : '';
      lines.push(`// ${r.sig}  →  ${r.existingName}  [${r.reason}]${loc}`);
    }
  }

  return { kotlin: lines.join('\n'), reuse, emitted, reused };
}

function composeTextStyleFields(s) {
  const fields = [];
  if (s.font) {
    // For Compose Multiplatform, `Font(Res.font.X, ...)` is @Composable-only,
    // so FontFamily must be built inside a composable scope. See theming.md
    // for the wrapper-function pattern. We leave fontFamily out of this val
    // so the file compiles; users apply it via `inter28Bold.copy(fontFamily = ...)`
    // inside their theme's @Composable appTypography() helper.
    fields.push(`// fontFamily = <apply via theme>   // design uses: "${s.font}"`);
  }
  if (s.size) fields.push(`fontSize = ${s.size}.sp`);
  const w = weightToCompose(s.weight);
  if (w) fields.push(`fontWeight = ${w}`);
  if (s.lineHeight) fields.push(`lineHeight = ${s.lineHeight}.sp`);
  if (s.letterSpacing) fields.push(`letterSpacing = ${s.letterSpacing}.sp`);
  if (s.align && ALIGN_MAP[s.align]) {
    fields.push(`textAlign = ${ALIGN_MAP[s.align]}`);
  }
  return fields.length ? fields : ['// no style fields captured'];
}

function sanitizeKotlinIdent(s) {
  return String(s).replace(/[^A-Za-z0-9]/g, '');
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
  const outDir = args.out || './kotlin-out';
  const pkg = args.package || 'com.example.ui.theme';

  let input;
  try {
    input = JSON.parse(fs.readFileSync(inputPath, 'utf8'));
  } catch (e) {
    console.error(`Could not read ${inputPath}: ${e.message}`);
    process.exit(1);
  }

  const root = input.layout || input;
  if (!root || typeof root !== 'object') {
    console.error('screen.json does not contain a `layout` object');
    process.exit(1);
  }

  // Scan existing repo tokens if --match-existing was provided
  let existingMaps = null;
  let existingSummary = null;
  if (args['match-existing']) {
    if (!fs.existsSync(args['match-existing'])) {
      console.error(`--match-existing path does not exist: ${args['match-existing']}`);
      process.exit(1);
    }
    const existing = scanExistingTokens(args['match-existing']);
    existingMaps = buildExistingTokenMaps(existing);
    existingSummary = {
      scannedPath: args['match-existing'],
      filesScanned: existing.filesScanned,
      existingColors: existing.colors.length,
      existingTextStyles: existing.textStyles.length,
    };
    console.log(`Scanned ${existing.filesScanned.length} .kt file(s) for existing tokens`);
    console.log(`  found ${existing.colors.length} colour(s), ${existing.textStyles.length} text style(s)`);
  }

  const colors = collectColors(root);
  const textStyles = collectTextStyles(root, input.textStyles || {});

  const colorResult = emitColorKt(colors, pkg, existingMaps);
  const typoResult = emitTypographyKt(textStyles, colors, pkg, existingMaps);

  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, 'Color.kt'), colorResult.kotlin);
  fs.writeFileSync(path.join(outDir, 'Typography.kt'), typoResult.kotlin);

  // Reuse map — this is what verify.js and the code-gen step consult so the
  // emitted Kotlin references existing repo tokens by their actual names.
  const reuseMap = {
    generatedAt: new Date().toISOString(),
    existingTokensSource: existingSummary,
    colors: colorResult.reuse,
    textStyles: typoResult.reuse,
  };
  fs.writeFileSync(
    path.join(outDir, 'figma-token-reuse.json'),
    JSON.stringify(reuseMap, null, 2),
  );

  const colorReuseCount = Object.values(colorResult.reuse).filter(r => r.reason !== 'new').length;
  const textReuseCount = Object.values(typoResult.reuse).filter(r => r.reason !== 'new').length;

  console.log(`Extracted ${colors.size} colors (${colorResult.emitted.length} new, ${colorReuseCount} reused), ${textStyles.size} text styles (${typoResult.emitted.length} new, ${textReuseCount} reused)`);
  console.log(`  -> ${path.resolve(outDir, 'Color.kt')}`);
  console.log(`  -> ${path.resolve(outDir, 'Typography.kt')}`);
  console.log(`  -> ${path.resolve(outDir, 'figma-token-reuse.json')}`);
}

if (require.main === module) {
  try { main(); }
  catch (e) { console.error('ERROR:', e.message); process.exit(1); }
}

module.exports = {
  parseRgba,
  toComposeColor,
  weightToCompose,
  textStyleKey,
  collectColors,
  collectTextStyles,
  camelCaseFromName,
  normaliseName,
  parseKotlinTokens,
  scanExistingTokens,
  buildExistingTokenMaps,
  rgbaToHexKey,
  emitColorKt,
  emitTypographyKt,
};
