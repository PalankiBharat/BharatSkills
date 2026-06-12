#!/usr/bin/env node
/**
 * svg-to-xml.js
 *
 * Convert the SVG icons exported by figma-to-json.js into Android
 * VectorDrawable XML files, placed in the right directory for either a
 * standard Android project (`res/drawable/`) or a Compose Multiplatform
 * project (`commonMain/composeResources/drawable/`).
 *
 * Handles the common case that Figma exports cleanly: single-layer icons
 * with a mix of paths, solid fills, fill-opacity, and fillRule. Gradients,
 * clipPaths, masks, text elements, and `<use>` are rejected with a clear
 * message suggesting Valkyrie for those files.
 *
 * Usage:
 *   node svg-to-xml.js <input-dir> --out <output-dir> [--target kmp|android]
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
  console.log(`Usage: node svg-to-xml.js <input-dir> [options]

Required:
  <input-dir>         Directory of .svg files to convert

Options:
  --out <dir>         Output directory (default depends on --target)
  --target <tgt>      'kmp' (default) or 'android'
                      kmp     → <project>/composeResources/drawable/
                      android → <project>/res/drawable/
  --project <dir>     Base path of the target project (when --out not given)
  --prefix <str>      Prefix for generated filenames (default: "ic_")
  --help              Show this message

Each .svg becomes an .xml file with a valid Android resource name
(lowercase, underscores). If any SVG can't be cleanly converted
(gradients, clip paths, etc.), it's skipped and listed at the end with a
recommendation to use Valkyrie for that file.
`);
}

// ============================================================================
// SVG attribute extraction (narrow regex, not a full DOM parser)
// ============================================================================

/**
 * Pull the attributes of a specific tag from SVG source. Returns an array
 * of objects, one per occurrence. Self-closing and paired tags both work.
 */
function extractTags(svgText, tagName) {
  const out = [];
  // Matches <tag ... /> and <tag ...>content</tag>
  const re = new RegExp(
    `<${tagName}\\b([^>]*?)(?:/>|>([\\s\\S]*?)</${tagName}>)`,
    'g',
  );
  let m;
  while ((m = re.exec(svgText)) !== null) {
    out.push({ attrs: parseAttrs(m[1]), body: m[2] || '', raw: m[0] });
  }
  return out;
}

function parseAttrs(attrString) {
  const attrs = {};
  const re = /([a-zA-Z_:][a-zA-Z0-9_:\-.]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
  let m;
  while ((m = re.exec(attrString)) !== null) {
    attrs[m[1]] = m[2] !== undefined ? m[2] : m[3];
  }
  return attrs;
}

/** Strict check: the SVG contains features we don't convert. */
function findUnsupported(svgText) {
  const bad = [];
  if (/<linearGradient\b/i.test(svgText)) bad.push('linearGradient');
  if (/<radialGradient\b/i.test(svgText)) bad.push('radialGradient');
  if (/<pattern\b/i.test(svgText)) bad.push('pattern');
  if (/<clipPath\b/i.test(svgText)) bad.push('clipPath');
  if (/<mask\b/i.test(svgText)) bad.push('mask');
  if (/<filter\b/i.test(svgText)) bad.push('filter');
  if (/<text\b/i.test(svgText)) bad.push('text');
  if (/<use\b/i.test(svgText)) bad.push('use');
  if (/<image\b/i.test(svgText)) bad.push('image');
  if (/<foreignObject\b/i.test(svgText)) bad.push('foreignObject');
  // References to a gradient/clipPath by URL
  if (/fill\s*=\s*["']url\(/i.test(svgText)) bad.push('url() fill (gradient ref)');
  if (/stroke\s*=\s*["']url\(/i.test(svgText)) bad.push('url() stroke (gradient ref)');
  // Transforms on individual paths — we don't bake them into pathData
  if (/<path\b[^>]*\btransform\s*=/i.test(svgText)) bad.push('transform on path');
  return bad;
}

// ============================================================================
// Colour conversion
// ============================================================================

/**
 * Convert an SVG colour string + fill-opacity into VectorDrawable's
 * #AARRGGBB format. Handles: #RGB, #RRGGBB, #RRGGBBAA, named colours
 * (black/white), rgb()/rgba(), "none", and "currentColor".
 */
function svgColorToAndroid(fill, fillOpacity) {
  if (fill == null) return null;
  const f = String(fill).trim().toLowerCase();
  if (f === 'none' || f === 'transparent') return null;
  if (f === 'currentcolor') {
    // VectorDrawable can tint at runtime via `android:tint`, so we emit
    // black here and rely on caller to apply a tint.
    return bakeAlpha('#000000', fillOpacity);
  }

  // Named colours (common subset; Figma mostly uses hex but just in case)
  const NAMED = {
    black: '#000000', white: '#FFFFFF', red: '#FF0000', green: '#008000',
    blue: '#0000FF', yellow: '#FFFF00', gray: '#808080', grey: '#808080',
  };
  if (NAMED[f]) return bakeAlpha(NAMED[f], fillOpacity);

  // #RGB / #RRGGBB / #RRGGBBAA
  let m = /^#([0-9a-f]{3})$/.exec(f);
  if (m) {
    const [r, g, b] = m[1].split('');
    return bakeAlpha(`#${r}${r}${g}${g}${b}${b}`, fillOpacity);
  }
  m = /^#([0-9a-f]{6})$/.exec(f);
  if (m) return bakeAlpha(`#${m[1]}`, fillOpacity);
  m = /^#([0-9a-f]{8})$/.exec(f);
  if (m) {
    // SVG uses #RRGGBBAA; Android uses #AARRGGBB — reorder
    const rrggbb = m[1].slice(0, 6);
    const aa = m[1].slice(6, 8);
    return `#${aa.toUpperCase()}${rrggbb.toUpperCase()}`;
  }

  // rgb(r,g,b) / rgba(r,g,b,a)
  m = /^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)$/.exec(f);
  if (m) {
    const r = Number(m[1]), g = Number(m[2]), b = Number(m[3]);
    const a = m[4] != null ? Number(m[4]) : 1;
    const hex = '#' + [r, g, b].map(n => n.toString(16).padStart(2, '0')).join('');
    return bakeAlpha(hex, fillOpacity != null ? Number(fillOpacity) * a : a);
  }

  // Unknown — caller handles
  return null;
}

function bakeAlpha(rrggbb, fillOpacity) {
  const alpha = fillOpacity != null ? Number(fillOpacity) : 1;
  const clamped = Math.max(0, Math.min(1, alpha));
  const aa = Math.round(clamped * 255).toString(16).padStart(2, '0').toUpperCase();
  return `#${aa}${rrggbb.slice(1).toUpperCase()}`;
}

// ============================================================================
// SVG → VectorDrawable
// ============================================================================

const FILL_RULE_MAP = { evenodd: 'evenOdd', nonzero: 'nonZero' };

/**
 * Convert a single SVG document string to VectorDrawable XML.
 * Returns { xml } on success or { error, unsupported: [...] } on failure.
 */
function svgToVectorDrawable(svgText) {
  const unsupported = findUnsupported(svgText);
  if (unsupported.length) {
    return {
      error: `unsupported SVG features: ${unsupported.join(', ')}`,
      unsupported,
    };
  }

  const svgTags = extractTags(svgText, 'svg');
  if (!svgTags.length) return { error: 'no <svg> root element found' };
  const svgAttrs = svgTags[0].attrs;

  // Dimensions: prefer viewBox for intrinsic coordinate system; fall back
  // to width/height attributes
  let vpW, vpH, wDp, hDp;
  if (svgAttrs.viewBox) {
    const parts = svgAttrs.viewBox.split(/[\s,]+/).map(Number);
    if (parts.length === 4) {
      vpW = parts[2];
      vpH = parts[3];
    }
  }
  wDp = parseDimension(svgAttrs.width) ?? vpW ?? 24;
  hDp = parseDimension(svgAttrs.height) ?? vpH ?? 24;
  vpW = vpW ?? wDp;
  vpH = vpH ?? hDp;

  const pathTags = extractTags(svgText, 'path');
  if (!pathTags.length) return { error: 'no <path> elements in <svg>' };

  const pathXml = [];
  for (const tag of pathTags) {
    const a = tag.attrs;
    if (!a.d) continue;
    const fill = svgColorToAndroid(a.fill, a['fill-opacity']);
    const stroke = svgColorToAndroid(a.stroke, a['stroke-opacity']);
    const fillType = FILL_RULE_MAP[(a['fill-rule'] || '').toLowerCase()];

    const attrs = [`android:pathData="${escapeXml(a.d)}"`];
    if (fill) attrs.push(`android:fillColor="${fill}"`);
    if (stroke) {
      attrs.push(`android:strokeColor="${stroke}"`);
      if (a['stroke-width']) attrs.push(`android:strokeWidth="${Number(a['stroke-width'])}"`);
    }
    if (fillType) attrs.push(`android:fillType="${fillType}"`);

    pathXml.push(`    <path\n        ${attrs.join('\n        ')}/>`);
  }

  if (!pathXml.length) return { error: 'no convertible <path> elements' };

  const xml =
    `<?xml version="1.0" encoding="utf-8"?>\n` +
    `<vector xmlns:android="http://schemas.android.com/apk/res/android"\n` +
    `    android:width="${wDp}dp"\n` +
    `    android:height="${hDp}dp"\n` +
    `    android:viewportWidth="${vpW}"\n` +
    `    android:viewportHeight="${vpH}">\n` +
    pathXml.join('\n') +
    `\n</vector>\n`;

  return { xml };
}

function parseDimension(s) {
  if (!s) return null;
  const m = /^([\d.]+)/.exec(String(s));
  return m ? Number(m[1]) : null;
}

function escapeXml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

// ============================================================================
// Filename mapping
// ============================================================================

function toResourceName(basename, prefix) {
  // "Union", "ic-search", "Weiter-Button" → "ic_union", "ic_search", "ic_weiter_button"
  let clean = basename
    .replace(/\.[^.]+$/, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (!clean) clean = 'asset';
  // Drawable resource names must start with a letter, not a digit
  if (/^[0-9]/.test(clean)) clean = `a_${clean}`;
  const pfx = prefix || '';
  return clean.startsWith(pfx) ? clean : `${pfx}${clean}`;
}

// ============================================================================
// Main
// ============================================================================

function resolveOutputDir(args) {
  if (args.out) return args.out;
  const target = (args.target || 'kmp').toLowerCase();
  const base = args.project || '.';
  if (target === 'kmp') {
    return path.join(base, 'composeResources', 'drawable');
  }
  if (target === 'android') {
    return path.join(base, 'res', 'drawable');
  }
  throw new Error(`Unknown --target: ${args.target}`);
}

function main() {
  const args = parseArgs(process.argv);
  if (args.help || !args.positional[0]) {
    usage();
    process.exit(args.help ? 0 : 1);
  }

  const inputDir = args.positional[0];
  if (!fs.existsSync(inputDir)) {
    console.error(`Input directory not found: ${inputDir}`);
    process.exit(2);
  }

  const outDir = resolveOutputDir(args);
  const prefix = args.prefix != null ? args.prefix : 'ic_';
  fs.mkdirSync(outDir, { recursive: true });

  const files = fs.readdirSync(inputDir).filter(f => f.toLowerCase().endsWith('.svg'));
  const successes = [];
  const failures = [];

  for (const file of files) {
    const srcPath = path.join(inputDir, file);
    const svgText = fs.readFileSync(srcPath, 'utf8');
    const resName = toResourceName(file, prefix);
    const result = svgToVectorDrawable(svgText);
    if (result.error) {
      failures.push({ file, resName, error: result.error });
      continue;
    }
    const outPath = path.join(outDir, `${resName}.xml`);
    fs.writeFileSync(outPath, result.xml);
    successes.push({ file, resName, outPath });
  }

  console.log(`Converted ${successes.length}/${files.length} SVG(s) to VectorDrawable.`);
  console.log(`  output -> ${path.resolve(outDir)}`);
  if (successes.length) {
    console.log('');
    for (const s of successes.slice(0, 10)) {
      console.log(`  ✓ ${s.file} → ${s.resName}.xml`);
    }
    if (successes.length > 10) console.log(`  …and ${successes.length - 10} more`);
  }

  if (failures.length) {
    console.log('');
    console.log(`${failures.length} file(s) could not be auto-converted:`);
    for (const f of failures) {
      console.log(`  ✗ ${f.file}: ${f.error}`);
    }
    console.log('');
    console.log('For these, use Valkyrie (https://github.com/ComposeGears/Valkyrie) —');
    console.log('it handles gradients, clip paths, and complex transforms that the');
    console.log('simple converter here does not.');
  }

  // Non-zero exit only if nothing converted at all; partial success is fine
  process.exit(successes.length === 0 && files.length > 0 ? 1 : 0);
}

if (require.main === module) {
  try { main(); }
  catch (e) { console.error('ERROR:', e.message); process.exit(2); }
}

module.exports = {
  svgToVectorDrawable,
  svgColorToAndroid,
  toResourceName,
  findUnsupported,
};
