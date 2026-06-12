#!/usr/bin/env node
/**
 * figma-to-json.js
 *
 * Export a Figma frame (via its URL) to a JSON layout representation plus
 * asset files: SVGs for vector icons, PNGs for raster images.
 *
 * Requires: Node 18+ (uses global fetch). No npm dependencies.
 *
 * Usage:
 *   FIGMA_TOKEN=xxx node figma-to-json.js "<figma-url>"
 *
 * See `node figma-to-json.js --help` or README.md for full docs.
 */

'use strict';

const fs = require('fs/promises');
const path = require('path');

// ============================================================================
// CLI
// ============================================================================

function parseArgs(argv) {
  const args = { positional: [] };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--help' || a === '-h') args.help = true;
    else if (a === '--full-json') args.fullJson = true;
    else if (a === '--include-hidden') args.includeHidden = true;
    else if (a === '--emit-root-bitmap') args.emitRootBitmap = true;
    else if (a === '--verbose') args.verbose = true;           // legacy verbose output
    else if (a === '--compact') args.compact = true;           // explicit opt-in (on by default anyway)
    else if (a === '--keep-ids') args.keepIds = true;          // preserve Figma IDs in output
    else if (a === '--all-frames') args.allFrames = true;      // export every frame on the page/section
    else if (a.startsWith('--')) args[a.slice(2)] = argv[++i];
    else args.positional.push(a);
  }
  return args;
}

function usage() {
  console.log(`Usage: node figma-to-json.js "<figma-url>" [options]

Options:
  --token <pat>       Figma Personal Access Token (or FIGMA_TOKEN env var)
  --out <dir>         Output directory (default: ./figma-export)
  --scale <n>         PNG scale 1-4 (default: 2)
  --batch <n>         Image export batch size (default: 40)
  --max-wait <sec>    Max Retry-After to honor before bailing (default: 600)
  --all-frames        Export every top-level frame on the page (or section) as
                      a separate screen directory, instead of just the first.
                      Writes an index.json manifest at the output root.
                      Note: URLs whose node-id points at a Figma SECTION or a
                      page (CANVAS) are auto-split per-frame even without this
                      flag — a single tree spanning N screens is never useful.
  --include-hidden    Include nodes marked visible=false
  --emit-root-bitmap  Emit the root frame as a PNG even when it has structured
                      descendants. Default is off — root-level PNG exports
                      and image fills are treated as handoff annotations and
                      the structure is walked instead.
  --verbose           Emit the full screen.json (legacy format): rgba strings,
                      ids on every node, repeated text styles inlined, zero
                      values retained, single-child frames not unwrapped.
                      Default is the compact format.
  --keep-ids          Keep Figma node IDs in the output even in compact mode.
                      Useful for debugging or tool integrations that need
                      stable node references; off by default.
  --full-json         Also write raw Figma node JSON for debugging
  --help              Show this message
`);
}

// ============================================================================
// URL parsing
// ============================================================================

/**
 * Parse a Figma URL into { fileKey, nodeId }.
 * Handles: /file/, /design/, /proto/, /board/; branches; embed URLs;
 * URL-encoded node-ids; comma-separated node-ids (first wins).
 * Rejects community URLs with a clear error.
 */
function parseFigmaUrl(input) {
  const trimmed = String(input || '').trim();
  if (!trimmed) throw new Error('Empty URL');

  let u;
  try { u = new URL(trimmed); }
  catch { throw new Error(`Invalid URL: ${trimmed}`); }

  if (!/(^|\.)figma\.com$/i.test(u.hostname)) {
    throw new Error(`Not a figma.com URL: ${u.hostname}`);
  }

  // Unwrap embed URLs: figma.com/embed?embed_host=x&url=<real-url>
  if (u.pathname.replace(/^\/+|\/+$/g, '') === 'embed') {
    const wrapped = u.searchParams.get('url');
    if (!wrapped) throw new Error('Embed URL missing ?url= parameter');
    return parseFigmaUrl(wrapped);
  }

  const parts = u.pathname.split('/').filter(Boolean);

  if (parts[0] && parts[0].toLowerCase() === 'community') {
    throw new Error(
      'Community file URLs are not accessible via REST API. ' +
      'Open the file in Figma, duplicate it to your workspace, then use that URL instead.'
    );
  }

  const typeIdx = parts.findIndex(p =>
    ['file', 'design', 'proto', 'board'].includes(p.toLowerCase())
  );
  if (typeIdx === -1 || !parts[typeIdx + 1]) {
    throw new Error('Could not extract file key from URL path');
  }
  let fileKey = parts[typeIdx + 1];

  // Branch URLs — /design/MAIN/branch/BRANCH/name. The branch has its own file key.
  const branchIdx = parts.indexOf('branch');
  if (branchIdx !== -1 && parts[branchIdx + 1]) {
    fileKey = parts[branchIdx + 1];
  }

  // node-id extraction. Figma URLs use `-` as the separator; the API wants `:`.
  // Encoded forms like `%3A` decode to `:` via searchParams, so we only do the
  // dash-to-colon replacement when no `:` is already present.
  let rawNodeId = u.searchParams.get('node-id');
  let nodeId = null;
  if (rawNodeId) {
    rawNodeId = rawNodeId.trim();
    if (rawNodeId.includes(',')) {
      const first = rawNodeId.split(',')[0];
      console.error(`Note: multiple node-ids in URL; using first: ${first}`);
      rawNodeId = first;
    }
    nodeId = rawNodeId.includes(':') ? rawNodeId : rawNodeId.replace(/-/g, ':');
  }

  return { fileKey, nodeId };
}

// ============================================================================
// API client
// ============================================================================

const BASE = 'https://api.figma.com/v1';
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

/**
 * Fetch with retries on 429, 5xx, and network errors.
 * Parses 4xx errors into useful messages.
 */
async function figmaFetch(url, token, {
  attempt = 1, maxAttempts = 4, maxWaitSec = 600,
} = {}) {
  let res;
  try {
    res = await fetch(url, { headers: { 'X-Figma-Token': token } });
  } catch (e) {
    if (attempt >= maxAttempts) {
      throw new Error(`Network error after ${attempt} attempts: ${e.message}`);
    }
    const backoff = 1000 * 2 ** (attempt - 1);
    console.error(`  [network] ${e.message} — retry in ${backoff}ms`);
    await sleep(backoff);
    return figmaFetch(url, token, { attempt: attempt + 1, maxAttempts, maxWaitSec });
  }

  // 429 — respect Retry-After, bail if it's absurd
  if (res.status === 429) {
    const retryAfter = Number(res.headers.get('retry-after')) || 60;
    const planTier = res.headers.get('x-figma-plan-tier') || 'unknown';
    const limitType = res.headers.get('x-figma-rate-limit-type') || 'unknown';
    if (retryAfter > maxWaitSec) {
      throw new Error(
        `Rate limited (429). Retry-After=${retryAfter}s (~${Math.round(retryAfter / 3600)}h). ` +
        `plan=${planTier} limit-type=${limitType}. ` +
        `Your quota is exhausted. ` +
        `If you're on Free/Starter, move the file to a Pro team workspace (Drafts use free-tier limits).`
      );
    }
    if (attempt >= maxAttempts) {
      throw new Error(`Rate limited (429) after ${attempt} attempts; Retry-After=${retryAfter}s`);
    }
    console.error(`  [429] waiting ${retryAfter}s (retry ${attempt + 1}/${maxAttempts})...`);
    await sleep(retryAfter * 1000);
    return figmaFetch(url, token, { attempt: attempt + 1, maxAttempts, maxWaitSec });
  }

  // 5xx — retry with exponential backoff
  if (res.status >= 500 && res.status < 600) {
    if (attempt >= maxAttempts) {
      const body = await res.text().catch(() => '');
      throw new Error(`Figma ${res.status} after ${attempt} attempts: ${body.slice(0, 200)}`);
    }
    const backoff = 1000 * 2 ** (attempt - 1);
    console.error(`  [${res.status}] retry in ${backoff}ms (${attempt + 1}/${maxAttempts})`);
    await sleep(backoff);
    return figmaFetch(url, token, { attempt: attempt + 1, maxAttempts, maxWaitSec });
  }

  // 4xx — don't retry, format a useful message
  if (!res.ok) {
    const ct = res.headers.get('content-type') || '';
    let detail = '';
    if (ct.includes('application/json')) {
      try {
        const body = await res.json();
        if (body.err) detail = body.err;
        else detail = JSON.stringify(body).slice(0, 200);
      } catch { /* fall through */ }
    }
    if (!detail) {
      const body = await res.text().catch(() => '');
      detail = body.slice(0, 200);
    }
    let hint = '';
    if (res.status === 401) hint = ' — token missing or invalid.';
    else if (res.status === 403) hint = ' — token lacks access to this file; needs file_content:read scope.';
    else if (res.status === 404) hint = ' — file/node not found, or you don\'t have access (Figma hides 403 as 404).';
    else if (res.status === 400) hint = ' — bad request; check node-id format.';
    throw new Error(`Figma API ${res.status}: ${detail}${hint}`);
  }

  // 2xx — expect JSON
  const ct = res.headers.get('content-type') || '';
  if (!ct.includes('application/json')) {
    const body = await res.text().catch(() => '');
    throw new Error(`Expected JSON response, got content-type=${ct}: ${body.slice(0, 200)}`);
  }
  const data = await res.json();
  if (data.err) throw new Error(`Figma API returned err: ${data.err}`);
  return data;
}

async function getNodes(fileKey, nodeIds, token, opts) {
  const ids = encodeURIComponent(nodeIds.join(','));
  return figmaFetch(`${BASE}/files/${fileKey}/nodes?ids=${ids}`, token, opts);
}

async function getFile(fileKey, token, { depth = 2 } = {}, opts = {}) {
  return figmaFetch(`${BASE}/files/${fileKey}?depth=${depth}`, token, opts);
}

/**
 * Export images for a batch of node IDs.
 * Returns { urls: {id: url}, failed: [id] }.
 * Failed = nodes Figma couldn't render (null URL in response).
 */
async function exportImages(fileKey, ids, { format, scale }, token, opts) {
  if (!ids.length) return { urls: {}, failed: [] };
  const idsParam = encodeURIComponent(ids.join(','));
  let url = `${BASE}/images/${fileKey}?ids=${idsParam}&format=${format}`;
  if (format === 'png' || format === 'jpg') url += `&scale=${scale}`;
  const data = await figmaFetch(url, token, opts);
  const urls = {};
  const failed = [];
  for (const id of ids) {
    const u = data.images && data.images[id];
    if (u) urls[id] = u;
    else failed.push(id);
  }
  return { urls, failed };
}

// ============================================================================
// Node classification
//
// IMPORTANT DESIGN CONSTRAINT: classification NEVER stops the tree walk.
// Asset classification produces metadata ("this node should ALSO render as a
// bitmap"). The walk itself always descends into every visible child. This
// is what lets us represent a screen as its real component tree (chip rows,
// cards, text) even if a designer has attached a PNG export setting to the
// root frame for handoff purposes.
//
// A node is marked as a leaf asset (walk stops) ONLY in these cases:
//   - It's a primitive vector shape (VECTOR, BOOLEAN_OPERATION) — the shape
//     IS its own content; any children are just render-composition primitives.
//   - It's a small icon-shaped container whose children are all vector
//     primitives — flattening to one SVG is correct and walking further would
//     produce useless noise like "<ELLIPSE, RECTANGLE>".
//
// Anything else that's classified as an asset is a DECORATION on a container
// that still walks: a card with an image background, a hero banner that also
// has text overlaid on it.
// ============================================================================

const VECTOR_CHILD_TYPES = new Set([
  'VECTOR', 'BOOLEAN_OPERATION', 'GROUP',
  'ELLIPSE', 'RECTANGLE', 'STAR', 'LINE', 'REGULAR_POLYGON',
]);

// Types that constitute "real structure" — if any of these are reachable
// under a node, we walk into it rather than flatten it to a bitmap.
const STRUCTURED_DESCENDANT_TYPES = new Set([
  'TEXT', 'INSTANCE', 'COMPONENT', 'COMPONENT_SET', 'FRAME', 'SECTION',
]);

const ICON_ROOTS = /\b(icon|ic|arrow|chevron|caret|logo|symbol|glyph)\b/;

function hasIconNameHint(name) {
  if (!name) return false;
  const normalized = String(name)
    .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
    .replace(/([A-Z])([A-Z][a-z])/g, '$1-$2')
    .replace(/_/g, '-')
    .toLowerCase();
  return ICON_ROOTS.test(normalized);
}

function hasExplicitExport(node, ...formats) {
  if (!Array.isArray(node.exportSettings)) return false;
  const wanted = new Set(formats.map(f => f.toUpperCase()));
  return node.exportSettings.some(s => s.format && wanted.has(s.format.toUpperCase()));
}

function hasImageFill(node) {
  const fills = node.fills || node.background || [];
  return Array.isArray(fills) &&
    fills.some(p => p && p.type === 'IMAGE' && p.visible !== false);
}

/**
 * Does this subtree contain any real structure (text, instances, nested
 * frames)? If yes, the node is a container — we walk it for the structure,
 * not flatten it to a bitmap.
 *
 * Budget is a max-node-visit cap to keep this cheap on pathological trees.
 */
function hasStructuredDescendants(node, budget = 200) {
  if (!node || budget <= 0) return { found: false, remaining: budget };
  if (!Array.isArray(node.children)) return { found: false, remaining: budget };
  let remaining = budget;
  for (const c of node.children) {
    if (!c || c.visible === false) continue;
    remaining--;
    if (STRUCTURED_DESCENDANT_TYPES.has(c.type)) {
      return { found: true, remaining };
    }
    const res = hasStructuredDescendants(c, remaining);
    remaining = res.remaining;
    if (res.found) return { found: true, remaining };
    if (remaining <= 0) break;
  }
  return { found: false, remaining };
}

/**
 * Decide whether a node should ALSO render as a bitmap asset.
 * Returns { kind: 'icon'|'image', isLeafIcon: boolean } or null.
 *
 * `isLeafIcon: true` is the ONLY case in which the tree walker stops
 * descending. It means "this is a flat icon; its children are just shape
 * primitives that compose the icon, not real UI."
 *
 * Options:
 *   - `isRoot`: true when this is the entry-point node of the export
 *   - `skipRootBitmap`: if true (default), the root is NOT emitted as a
 *     bitmap when it has structured descendants — designers routinely add
 *     PNG exportSettings to handoff frames and the skill prefers structure.
 */
function classifyNode(node, opts = {}) {
  const box = node.absoluteBoundingBox;
  if (!box || !(box.width > 0) || !(box.height > 0)) return null;

  const isContainer = ['FRAME', 'COMPONENT', 'INSTANCE', 'GROUP', 'SECTION'].includes(node.type);
  const visibleKids = Array.isArray(node.children)
    ? node.children.filter(c => c && c.visible !== false)
    : [];
  const hasStructure = isContainer && visibleKids.length > 0
    && hasStructuredDescendants(node).found;

  // Rule 1: Pure vector shape → leaf icon. Walking stops here.
  if (node.type === 'VECTOR' || node.type === 'BOOLEAN_OPERATION') {
    return { kind: 'icon', isLeafIcon: true };
  }

  // Rule 2: Small icon-shaped container with only vector children.
  // Flattening to one SVG is correct; further walking is useless.
  if (isContainer && visibleKids.length > 0) {
    const small = box.width <= 80 && box.height <= 80;
    const named = hasIconNameHint(node.name);
    const onlyVectors = visibleKids.every(c => VECTOR_CHILD_TYPES.has(c.type));
    if (onlyVectors && (small || named)) {
      return { kind: 'icon', isLeafIcon: true };
    }
  }

  // Rule 3: Explicit exportSettings — a hint from the designer.
  // Critically, this is NOT an instruction to flatten. If the node has
  // real structure underneath, the export is decorative and we keep walking.
  if (hasExplicitExport(node, 'SVG')) {
    if (hasStructure) return { kind: 'icon', isLeafIcon: false };
    return { kind: 'icon', isLeafIcon: !isContainer || visibleKids.length === 0 };
  }
  if (hasExplicitExport(node, 'PNG', 'JPG')) {
    // Root override: screens tagged for PNG export are almost always handoff
    // annotations. Skip the bitmap entirely when the screen has structure.
    if (opts.isRoot && opts.skipRootBitmap !== false && hasStructure) {
      return null;
    }
    if (hasStructure) return { kind: 'image', isLeafIcon: false };
    return { kind: 'image', isLeafIcon: !isContainer || visibleKids.length === 0 };
  }

  // Rule 4: Image fill — photo backgrounds, hero images.
  // Same "prefer structure" rule: if the container has text/instances/frames
  // underneath, the image fill is a background and we keep walking.
  if (hasImageFill(node)) {
    if (opts.isRoot && opts.skipRootBitmap !== false && hasStructure) {
      return null;
    }
    if (hasStructure) return { kind: 'image', isLeafIcon: false };
    // Leaf rectangle with an image fill: the shape IS the image.
    return { kind: 'image', isLeafIcon: !isContainer || visibleKids.length === 0 };
  }

  // No asset emission at this node. The walker will still descend.
  return null;
}

/**
 * Walk the tree and collect nodes that should emit bitmap assets.
 *
 * Contract: this function always recurses into every visible child UNLESS
 * the current node was classified as a leaf icon (`isLeafIcon: true`).
 * An asset classification that is NOT a leaf icon is a decoration — we
 * record it AND keep walking.
 *
 * The root node is processed regardless of its own visibility; descendants
 * respect `visible` unless --include-hidden.
 */
function classifyTree(node, acc, opts, depth = 0) {
  if (!node) return;
  if (depth > 0 && node.visible === false && !opts.includeHidden) return;

  const classifyOpts = {
    isRoot: depth === 0,
    skipRootBitmap: opts.skipRootBitmap !== false,
  };
  const c = classifyNode(node, classifyOpts);
  if (c) {
    acc.push({
      id: node.id,
      name: node.name,
      type: node.type,
      kind: c.kind,
      isLeafIcon: c.isLeafIcon,
    });
    // Leaf icons are the ONLY stop condition.
    if (c.isLeafIcon) return;
  }

  if (Array.isArray(node.children)) {
    for (const child of node.children) classifyTree(child, acc, opts, depth + 1);
  }
}

// Back-compat: old name for callers/tests that still import `collectAssets`.
const collectAssets = classifyTree;

// ============================================================================
// JSON simplification
// ============================================================================

const round2 = (n) => Math.round(n * 100) / 100;
const round0 = (n) => Math.round(n);

function firstSolidFill(n) {
  return (n.fills || []).find(f => f && f.type === 'SOLID' && f.visible !== false);
}

/**
 * Emit a colour in the format requested. `compact` → hex (`#RRGGBB` or
 * `#RRGGBBAA`); legacy verbose → `rgba(r, g, b, a)`. Hex is ~60% fewer
 * characters and Claude reads both forms equally well, but hex is the
 * convention Android/Compose developers actually use day-to-day.
 */
function paintToColor(p, compact = true) {
  if (!p || !p.color) return null;
  const { r, g, b, a } = p.color;
  const alpha = p.opacity != null ? p.opacity : (a != null ? a : 1);
  if (!compact) {
    return `rgba(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)}, ${round2(alpha)})`;
  }
  const rr = Math.round(r * 255).toString(16).padStart(2, '0').toUpperCase();
  const gg = Math.round(g * 255).toString(16).padStart(2, '0').toUpperCase();
  const bb = Math.round(b * 255).toString(16).padStart(2, '0').toUpperCase();
  // Omit alpha when it's fully opaque (the common case).
  if (alpha >= 0.999) return `#${rr}${gg}${bb}`;
  const aa = Math.round(alpha * 255).toString(16).padStart(2, '0').toUpperCase();
  return `#${rr}${gg}${bb}${aa}`;
}

// Back-compat alias for callers that haven't been updated yet.
const paintToRgba = (p) => paintToColor(p, false);

/**
 * Extract rotation (degrees) from a node's relativeTransform.
 * Figma stores 2D transforms as 2x3 matrix [[a,b,tx],[c,d,ty]].
 */
function extractRotation(node) {
  const t = node.relativeTransform;
  if (!Array.isArray(t) || t.length < 2) return 0;
  const [a, b] = t[0];
  const deg = Math.atan2(-b, a) * 180 / Math.PI;
  return Math.abs(deg) < 0.01 ? 0 : round2(deg);
}

function extractStroke(node, compact) {
  const strokes = node.strokes || [];
  const s = strokes.find(x => x && x.type === 'SOLID' && x.visible !== false);
  if (!s) return null;
  return {
    color: paintToColor(s, compact),
    weight: node.strokeWeight,
    align: node.strokeAlign,
  };
}

function extractEffects(node, compact) {
  const effects = (node.effects || []).filter(e => e && e.visible !== false);
  if (!effects.length) return null;
  return effects.map(e => {
    const out = { type: e.type };
    if (e.color) out.color = paintToColor({ color: e.color }, compact);
    if (e.offset) {
      const x = compact ? round0(e.offset.x) : round2(e.offset.x);
      const y = compact ? round0(e.offset.y) : round2(e.offset.y);
      if (x !== 0 || y !== 0) out.offset = { x, y };
    }
    if (typeof e.radius === 'number' && e.radius !== 0) out.blur = e.radius;
    if (typeof e.spread === 'number' && e.spread !== 0) out.spread = e.spread;
    return out;
  });
}

function hasMixedTextStyle(node) {
  if (node.type !== 'TEXT') return false;
  if (!Array.isArray(node.characterStyleOverrides)) return false;
  return node.characterStyleOverrides.some(x => x !== 0);
}

/**
 * Build a stable cache key for a text style so identical styles used in
 * many TEXT nodes collapse into one top-level entry. Colour is intentionally
 * excluded — in Compose, colour is a separate concern from the TextStyle.
 */
function textStyleSignature(s) {
  return JSON.stringify([
    s.font || '', s.size || 0, s.weight || 400,
    s.lineHeight || 0, s.letterSpacing || 0, s.align || '',
  ]);
}

/**
 * Is this lineHeight close enough to Figma's default (1.2× fontSize) that
 * we can omit it from the output? This removes noise on most TEXT nodes
 * since designers rarely override line height.
 */
function isDefaultLineHeight(lineHeightPx, fontSize) {
  if (!lineHeightPx || !fontSize) return true;
  const expected = fontSize * 1.2;
  return Math.abs(lineHeightPx - expected) < 0.5;
}

/**
 * If a node adds nothing beyond being an organisational wrapper (single
 * visible child, no layout/fill/stroke/effects/radius/opacity/rotation/
 * asset/text/border/componentId), replace it with its child. This strips
 * the "layer folder" frames Figma designers create for organisation that
 * don't carry any actual styling.
 */
function shouldUnwrap(out) {
  if (!out || !Array.isArray(out.children) || out.children.length !== 1) return false;
  const meaningful = [
    'fill', 'stroke', 'effects', 'layout', 'radius', 'opacity', 'rotation',
    'asset', 'text', 'componentId', 'styleRef',
  ];
  return !meaningful.some(k => out[k] !== undefined);
}

/**
 * simplify() — produce the compact JSON representation the skill emits
 * to screen.json. Context carries the compact flag, the existing asset map,
 * the per-node Figma style-id → name maps for style-ref annotations, and
 * a deduplication registry for text styles.
 *
 * ctx: {
 *   assetById, opts, compact, keepIds,
 *   styleNames: { [styleId]: { name, styleType } },     // from file response
 *   nodeStyleRefs: { [nodeId]: { fill, stroke, text, effect } },
 *   textStyles: { registry: { [sig]: key }, out: {} },
 *   parentLayoutMode: 'NONE' | 'HORIZONTAL' | 'VERTICAL',
 * }
 */
function simplify(node, ctx) {
  if (!node) return null;
  const opts = ctx.opts || {};
  if (node.visible === false && !opts.includeHidden) return null;

  const compact = ctx.compact !== false;
  const out = { name: node.name, type: node.type };
  if (ctx.keepIds || !compact) out.id = node.id;

  if (node.absoluteBoundingBox) {
    const b = node.absoluteBoundingBox;
    const roundFn = compact ? round0 : round2;
    const w = roundFn(b.width), h = roundFn(b.height);
    // Drop x/y on auto-layout children — they're implied by the parent's
    // direction + child order. Keep them on non-auto-layout parents.
    const insideAutoLayout = ctx.parentLayoutMode === 'HORIZONTAL' || ctx.parentLayoutMode === 'VERTICAL';
    if (compact && insideAutoLayout) {
      out.box = { w, h };
    } else {
      out.box = { x: roundFn(b.x), y: roundFn(b.y), w, h };
    }
  }

  const rotation = extractRotation(node);
  if (rotation !== 0) out.rotation = rotation;

  if (typeof node.opacity === 'number' && node.opacity !== 1) {
    out.opacity = round2(node.opacity);
  }

  const asset = ctx.assetById[node.id];
  if (asset) out.asset = { kind: asset.kind, path: asset.rel };

  // Figma style references: when a node has a named design-system style
  // applied (e.g. "primary", "body/lg"), surface it. This is the key signal
  // Claude should use to reuse existing repo tokens instead of inventing new
  // ones. We read from ctx.nodeStyleRefs (populated from the file response)
  // and ctx.styleNames (the top-level styles map).
  const nodeRefs = ctx.nodeStyleRefs && ctx.nodeStyleRefs[node.id];
  const styleNames = ctx.styleNames || {};
  if (nodeRefs) {
    const refs = {};
    for (const field of ['fill', 'stroke', 'text', 'effect', 'fills', 'strokes', 'effects']) {
      const sid = nodeRefs[field];
      if (sid && styleNames[sid]) {
        // Normalise field name: Figma sometimes returns 'fills' vs 'fill'
        const key = field.replace(/s$/, '');
        refs[key] = styleNames[sid].name;
      }
    }
    if (Object.keys(refs).length) out.styleRef = refs;
  }

  if (node.type === 'TEXT') {
    const s = node.style || {};
    const style = {};
    if (s.fontFamily) style.font = s.fontFamily;
    if (s.fontSize) style.size = s.fontSize;
    if (s.fontWeight && s.fontWeight !== 400) style.weight = s.fontWeight;
    if (!compact || !isDefaultLineHeight(s.lineHeightPx, s.fontSize)) {
      if (s.lineHeightPx) style.lineHeight = s.lineHeightPx;
    }
    if (s.letterSpacing && Math.abs(s.letterSpacing) > 0.01) {
      style.letterSpacing = s.letterSpacing;
    }
    if (s.textAlignHorizontal && s.textAlignHorizontal !== 'LEFT') {
      style.align = s.textAlignHorizontal;
    }

    const textOut = {
      content: node.characters,
      color: paintToColor(firstSolidFill(node), compact),
    };

    // In compact mode, dedupe text styles into a top-level registry.
    if (compact && ctx.textStyles && Object.keys(style).length) {
      const sig = textStyleSignature({
        font: style.font, size: style.size, weight: style.weight,
        lineHeight: style.lineHeight, letterSpacing: style.letterSpacing,
        align: style.align,
      });
      let key = ctx.textStyles.registry[sig];
      if (!key) {
        const size = style.size || 0;
        const weightName = ({
          300: 'Light', 400: 'Regular', 500: 'Medium',
          600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold',
        })[style.weight || 400] || 'Regular';
        const base = `${(style.font || 'text').replace(/\W/g, '')}${size}${weightName}`;
        key = base;
        let i = 2;
        while (Object.values(ctx.textStyles.registry).includes(key)) {
          key = `${base}_${i++}`;
        }
        ctx.textStyles.registry[sig] = key;
        ctx.textStyles.out[key] = style;
      }
      textOut.styleKey = key;
    } else {
      textOut.style = style;
    }

    if (hasMixedTextStyle(node)) textOut.mixedStyles = true;
    out.text = textOut;
  } else {
    const bg = firstSolidFill(node);
    if (bg) out.fill = paintToColor(bg, compact);
  }

  if (typeof node.cornerRadius === 'number' && node.cornerRadius !== 0) {
    out.radius = node.cornerRadius;
  }

  const stroke = extractStroke(node, compact);
  if (stroke) out.stroke = stroke;

  const effects = extractEffects(node, compact);
  if (effects) out.effects = effects;

  if (node.layoutMode && node.layoutMode !== 'NONE') {
    const layout = { mode: node.layoutMode };
    if (node.primaryAxisAlignItems && node.primaryAxisAlignItems !== 'MIN') {
      layout.primary = node.primaryAxisAlignItems;
    }
    if (node.counterAxisAlignItems && node.counterAxisAlignItems !== 'MIN') {
      layout.counter = node.counterAxisAlignItems;
    }
    if (node.itemSpacing && node.itemSpacing !== 0) {
      layout.gap = node.itemSpacing;
    }
    const pt = node.paddingTop || 0;
    const pr = node.paddingRight || 0;
    const pb = node.paddingBottom || 0;
    const pl = node.paddingLeft || 0;
    if (pt || pr || pb || pl) {
      // Collapse to a scalar when all four equal, to a pair when symmetric.
      if (pt === pr && pr === pb && pb === pl) {
        layout.padding = pt;
      } else if (pt === pb && pl === pr) {
        layout.padding = { v: pt, h: pl };
      } else {
        layout.padding = { t: pt, r: pr, b: pb, l: pl };
      }
    }
    out.layout = layout;
  }

  if (node.type === 'INSTANCE' && node.componentId) {
    out.componentId = node.componentId;
  }

  // Stop at leaf icons. Container assets (image-bg with kids) keep walking.
  if (asset && asset.isLeafIcon) return out;

  if (Array.isArray(node.children) && node.children.length) {
    const childCtx = { ...ctx, parentLayoutMode: node.layoutMode || 'NONE' };
    const kids = node.children
      .map(c => simplify(c, childCtx))
      .filter(Boolean);
    if (kids.length) out.children = kids;
  }

  // Unwrap single-child organisational frames in compact mode.
  if (compact && shouldUnwrap(out)) {
    return out.children[0];
  }

  return out;
}

// ============================================================================
// Filenames
// ============================================================================

const WINDOWS_RESERVED = new Set([
  'con', 'prn', 'aux', 'nul',
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
]);

const MAX_BASENAME_LEN = 100;

function sanitize(name) {
  let clean = String(name || 'asset')
    .trim()
    .replace(/[\/\\:*?"<>|]+/g, '-')
    .replace(/\s+/g, '-')
    .replace(/[^A-Za-z0-9._-]/g, '')
    .replace(/-+/g, '-')
    .replace(/^[-.]+|[-.]+$/g, '')
    .toLowerCase();

  if (!clean) clean = 'asset';
  if (clean.length > MAX_BASENAME_LEN) clean = clean.slice(0, MAX_BASENAME_LEN);
  if (WINDOWS_RESERVED.has(clean)) clean = `_${clean}`;
  return clean;
}

function uniquify(base, ext, used) {
  let name = `${base}.${ext}`;
  let i = 2;
  while (used.has(name)) name = `${base}-${i++}.${ext}`;
  used.add(name);
  return name;
}

// ============================================================================
// Downloads
// ============================================================================

async function downloadTo(url, filepath, { maxAttempts = 3 } = {}) {
  let lastErr;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const res = await fetch(url);
      if (!res.ok) {
        // Signed-URL 403/404 usually means expired; won't recover with retry
        if (res.status === 403 || res.status === 404) {
          throw new Error(`HTTP ${res.status} (non-retryable)`);
        }
        throw new Error(`HTTP ${res.status}`);
      }
      const buf = Buffer.from(await res.arrayBuffer());
      await fs.mkdir(path.dirname(filepath), { recursive: true });
      await fs.writeFile(filepath, buf);
      return buf.length;
    } catch (e) {
      lastErr = e;
      if (String(e.message).includes('non-retryable')) break;
      if (attempt < maxAttempts) await sleep(500 * 2 ** (attempt - 1));
    }
  }
  throw lastErr;
}

function chunk(arr, n) {
  const out = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
}

// ============================================================================
// Main
// ============================================================================

/**
 * Decide which frames a target node expands to.
 *
 * Returns { split, frames }:
 *   - split=true  → the node is a container of screens (CANVAS page, Figma
 *     SECTION, or --all-frames was passed) and `frames` are its top-level
 *     visible FRAME/COMPONENT children, each to be exported separately.
 *   - split=false, frames=[doc] → export the node itself as one screen.
 *   - split=false, frames=[]   → container with nothing exportable (error).
 */
function framesToExport(doc, allFrames) {
  const frameKids = (doc.children || []).filter(
    c => c && (c.type === 'FRAME' || c.type === 'COMPONENT') && c.visible !== false,
  );
  const isScreenContainer = doc.type === 'CANVAS' || doc.type === 'SECTION';
  if ((isScreenContainer || allFrames) && frameKids.length > 0) {
    return { split: true, frames: frameKids };
  }
  if (isScreenContainer) return { split: false, frames: [] };
  return { split: false, frames: [doc] };
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help || !args.positional[0]) {
    usage();
    process.exit(args.help ? 0 : 1);
  }

  const input = args.positional[0];
  const token = args.token || process.env.FIGMA_TOKEN;
  if (!token) {
    console.error('Missing token. Use --token <pat> or set FIGMA_TOKEN.');
    process.exit(1);
  }

  const outRoot = args.out || './figma-export';
  // scale 2: sharp enough to read icon glyphs and text in renders without
  // doubling download size for nothing (Figma caps at 4).
  const scale = Math.min(Math.max(Number(args.scale) || 2, 1), 4);
  // batch 40: the images API accepts larger id lists, but big batches raise
  // per-request render time and the blast radius of a single 429/timeout.
  const batchSize = Math.max(Number(args.batch) || 40, 1);
  // max-wait 600s: honors short Retry-After pauses (Pro-tier bursts) but
  // bails on the multi-hour waits that signal a Free/Starter-tier file.
  const maxWaitSec = Math.max(Number(args['max-wait']) || 600, 0);
  const opts = {
    includeHidden: !!args.includeHidden,
    // Default: skip bitmap emission at the root. A designer-attached PNG
    // exportSettings on a screen frame is almost always a handoff annotation,
    // not a request to flatten the screen to a bitmap. The --emit-root-bitmap
    // flag is the escape hatch for actual "this whole screen is one image"
    // intent.
    skipRootBitmap: !args.emitRootBitmap,
  };
  const fetchOpts = { maxWaitSec };

  const { fileKey, nodeId: urlNodeId } = parseFigmaUrl(input);
  console.log(`file=${fileKey}${urlNodeId ? ` node=${urlNodeId}` : ''}`);

  // ---------------------------------------------------------------------
  // Resolve export targets.
  //
  // One URL can legitimately mean N screens:
  //   - node-id points at a SECTION (the "batch of screens" container
  //     designers use) or a CANVAS (a whole page),
  //   - or the user passed --all-frames.
  // A single screen.json spanning ten screens is never what code generation
  // wants — each frame becomes its own export directory.
  // ---------------------------------------------------------------------
  let fileName;
  const targets = []; // [{ document, styles }]

  if (urlNodeId) {
    const resp = await getNodes(fileKey, [urlNodeId], token, fetchOpts);
    fileName = resp.name;
    const entry = resp.nodes && resp.nodes[urlNodeId];
    if (!entry || !entry.document) {
      throw new Error(
        `Node ${urlNodeId} not found in file ${fileKey}. ` +
        `It may have been deleted, or the node-id format in the URL is wrong.`
      );
    }
    const doc = entry.document;
    const styles = entry.styles || {};
    const { split, frames: resolved } = framesToExport(doc, !!args.allFrames);

    if (split) {
      console.log(
        `"${doc.name}" (${doc.type}) contains ${resolved.length} frame(s); exporting each separately.`
      );
      for (const f of resolved) targets.push({ document: f, styles });
    } else if (!resolved.length) {
      throw new Error(`"${doc.name}" (${doc.type}) contains no visible frames to export.`);
    } else {
      targets.push({ document: doc, styles });
    }
  } else {
    console.log('No node-id in URL; discovering frames on first page...');
    const file = await getFile(fileKey, token, { depth: 2 }, fetchOpts);
    fileName = file.name;
    const firstPage = (file.document.children || []).find(p => p.type === 'CANVAS');
    if (!firstPage) throw new Error('No pages found in file');
    const frames = (firstPage.children || []).filter(
      c => c && (c.type === 'FRAME' || c.type === 'COMPONENT') && c.visible !== false,
    );
    if (!frames.length) {
      throw new Error(
        `No frames on first page "${firstPage.name}". ` +
        `Pass a specific frame URL with ?node-id=... instead.`
      );
    }
    const chosen = args.allFrames ? frames : [frames[0]];
    if (!args.allFrames && frames.length > 1) {
      console.log(
        `note: page "${firstPage.name}" has ${frames.length} frames; ` +
        `exporting the first ("${frames[0].name}"). Pass --all-frames to export all of them.`
      );
    } else if (!args.allFrames) {
      console.log(`auto-selected: "${frames[0].name}" (${frames[0].id})`);
    }
    // depth:2 trees are shallow — fetch full subtrees for the chosen frames.
    const resp = await getNodes(fileKey, chosen.map(f => f.id), token, fetchOpts);
    for (const f of chosen) {
      const entry = resp.nodes && resp.nodes[f.id];
      if (!entry || !entry.document) {
        console.warn(`! frame "${f.name}" (${f.id}) could not be fetched; skipping.`);
        continue;
      }
      targets.push({ document: entry.document, styles: entry.styles || {} });
    }
    if (!targets.length) throw new Error('No frames could be fetched.');
  }

  // ---------------------------------------------------------------------
  // Export each target sequentially. Sequential (not parallel) on purpose:
  // image-export calls share one rate-limit budget, and interleaved logs
  // from parallel exports are unreadable.
  // ---------------------------------------------------------------------
  const exported = [];
  for (let i = 0; i < targets.length; i++) {
    const t = targets[i];
    if (targets.length > 1) console.log(`\n[${i + 1}/${targets.length}] "${t.document.name}"`);
    const screenDir = await exportOne(t.document, t.styles, {
      fileKey, fileName, outRoot, scale, batchSize, args, opts, fetchOpts, token,
    });
    exported.push({ name: t.document.name, id: t.document.id, dir: path.basename(screenDir) });
  }

  if (exported.length > 1) {
    await fs.writeFile(
      path.join(outRoot, 'index.json'),
      JSON.stringify(
        { fileKey, fileName, generatedAt: new Date().toISOString(), screens: exported },
        null, 2,
      ),
    );
    console.log(`\n✔ exported ${exported.length} screens -> ${path.resolve(outRoot)} (manifest: index.json)`);
  }
}

/**
 * Export a single frame subtree to `<outRoot>/<sanitized-name>/`:
 * screen.json + screen-render.png + assets/. Returns the screen directory.
 *
 * `rootNode` is the full Figma document subtree for the frame.
 * `styleNames` is the style-id → {name, styleType} map from the API response
 * that fetched this subtree (style names surface as styleRef in the output).
 */
async function exportOne(rootNode, styleNames, cfg) {
  const { fileKey, fileName, outRoot, scale, batchSize, args, opts, fetchOpts, token } = cfg;
  const targetNodeId = rootNode.id;

  // Prepare output directory.
  //
  // Collision guard: if a prior run wrote to the same `<outRoot>/<sanitized-name>`,
  // we don't want to overwrite it silently. Two different Figma frames named
  // "Screen" or "Page 1" sanitize to the same directory and would clobber
  // each other.
  //
  // Disambiguation strategy:
  //   1. If the frame has a generic name (Frame N, Screen, Page N, etc.),
  //      append the node ID directly — this is what users see in the URL
  //      and is the most recognisable reference point.
  //   2. If the frame has a real name but the directory already holds a
  //      different node's export, also append the node ID.
  //   3. Same node re-running over itself is allowed to overwrite.
  const GENERIC_NAME_RE = /^(frame|screen|page|group|component|untitled)(\s*\d+)?$/i;
  const rawName = String(rootNode.name || fileName || 'screen').trim();
  let screenDirName = sanitize(rawName);

  // Tier 1: generic name → preemptively suffix with node ID so multi-screen
  // exports of generically-named frames don't collide in the first place.
  if (GENERIC_NAME_RE.test(rawName)) {
    const idSuffix = sanitize(targetNodeId).replace(/^-+/, '');
    screenDirName = `${screenDirName}-${idSuffix}`;
  }
  let screenDir = path.join(outRoot, screenDirName);

  try {
    const existingScreenJson = path.join(screenDir, 'screen.json');
    const stat = await fs.stat(existingScreenJson).catch(() => null);
    if (stat) {
      const existingContent = JSON.parse(await fs.readFile(existingScreenJson, 'utf8'));
      const existingNodeId = (existingContent.screen && existingContent.screen.id) ||
        (existingContent.layout && existingContent.layout.id);
      if (existingNodeId && existingNodeId !== targetNodeId) {
        // Tier 2: real frame name but a different node already lives here.
        // Disambiguate with the node ID rather than a content hash; the ID
        // is what the user sees in the URL and recognises.
        const idSuffix = sanitize(targetNodeId).replace(/^-+/, '');
        screenDirName = `${screenDirName}-${idSuffix}`;
        screenDir = path.join(outRoot, screenDirName);
        console.warn(
          `! existing export at "${path.basename(path.dirname(existingScreenJson))}" is from a different node (${existingNodeId}); ` +
          `using "${screenDirName}" instead to avoid overwrite.`
        );
      }
      // Tier 3: existing node ID matches → same node re-running. Overwrite
      // is the expected behaviour.
    }
  } catch (e) {
    // If we can't read the existing screen.json (corrupt/incomplete prior run),
    // fall through to the default name; the run will overwrite. This is
    // appropriate for the recovery case.
  }

  await fs.mkdir(path.join(screenDir, 'assets', 'icons'), { recursive: true });
  await fs.mkdir(path.join(screenDir, 'assets', 'images'), { recursive: true });
  console.log(`output -> ${path.resolve(screenDir)}`);

  // Classify assets
  const assets = [];
  collectAssets(rootNode, assets, opts);
  const iconCount = assets.filter(a => a.kind === 'icon').length;
  const imageCount = assets.filter(a => a.kind === 'image').length;
  console.log(`classified ${assets.length} assets (${iconCount} icons, ${imageCount} images)`);

  // Assign filenames
  const used = new Set();
  for (const a of assets) {
    const base = sanitize(a.name);
    const ext = a.kind === 'icon' ? 'svg' : 'png';
    a.filename = uniquify(base, ext, used);
    a.rel = path.posix.join(
      'assets',
      a.kind === 'icon' ? 'icons' : 'images',
      a.filename,
    );
  }

  // Batched export
  const iconIds = assets.filter(a => a.kind === 'icon').map(a => a.id);
  const imageIds = assets.filter(a => a.kind === 'image').map(a => a.id);
  const urls = {};
  const renderFailed = [];

  for (const group of chunk(iconIds, batchSize)) {
    console.log(`  exporting SVG batch (${group.length})...`);
    const { urls: u, failed } = await exportImages(
      fileKey, group, { format: 'svg', scale: 1 }, token, fetchOpts,
    );
    Object.assign(urls, u);
    renderFailed.push(...failed);
  }
  for (const group of chunk(imageIds, batchSize)) {
    console.log(`  exporting PNG batch (${group.length}, @${scale}x)...`);
    const { urls: u, failed } = await exportImages(
      fileKey, group, { format: 'png', scale }, token, fetchOpts,
    );
    Object.assign(urls, u);
    renderFailed.push(...failed);
  }

  // Screen render — the full frame as a single high-res PNG. Claude reads
  // this alongside screen.json during code generation: the JSON is the
  // source of truth for data values (strings, hex codes, spacing numbers,
  // asset paths), but visual decisions (Row vs Column, weighted layouts,
  // chip vs button, alignment intent) come from the rendered image. Without
  // this, Claude has to infer layout intent from coordinates alone — which
  // is what produces the "everything is Box with offsets" failure mode.
  //
  // We use scale=2 by default (matches the existing image export scale) so
  // the render is sharp enough to read small UI details like icon glyphs
  // and text alignment without being wastefully large.
  console.log(`  exporting screen render (@${scale}x)...`);
  let screenRenderPath = null;
  try {
    const { urls: renderUrls, failed: renderFail } = await exportImages(
      fileKey, [targetNodeId], { format: 'png', scale }, token, fetchOpts,
    );
    if (renderUrls[targetNodeId]) {
      const renderRel = 'screen-render.png';
      await downloadTo(renderUrls[targetNodeId], path.join(screenDir, renderRel));
      screenRenderPath = renderRel;
    } else if (renderFail.length) {
      console.warn(`  ! screen render failed for ${targetNodeId} (will continue without it)`);
    }
  } catch (e) {
    // Don't fail the whole export if the render call has a hiccup — the JSON
    // pipeline can still proceed; Claude will fall back to JSON-only mode.
    console.warn(`  ! screen render error: ${e.message} (will continue without it)`);
  }

  // Download (signed S3 URLs — no rate limit, light parallelism)
  let downloaded = 0, failedCount = 0;
  const downloadErrors = [];
  const queue = assets.filter(a => urls[a.id]);
  // 6 workers: signed S3 URLs have no rate limit, so parallelism is safe;
  // 6 saturates a typical connection without piling up open sockets on
  // icon-heavy screens (50+ assets).
  const workers = Array.from({ length: 6 }, async () => {
    while (queue.length) {
      const a = queue.shift();
      try {
        await downloadTo(urls[a.id], path.join(screenDir, a.rel));
        downloaded++;
      } catch (e) {
        failedCount++;
        downloadErrors.push({ id: a.id, name: a.name, error: e.message });
        console.error(`  ! ${a.filename}: ${e.message}`);
      }
    }
  });
  await Promise.all(workers);
  console.log(`downloaded ${downloaded}, render-failed ${renderFailed.length}, download-failed ${failedCount}`);

  // Write JSON; omit assets that failed so consumers don't reference missing files
  const failedIds = new Set([...renderFailed, ...downloadErrors.map(e => e.id)]);
  const assetById = {};
  for (const a of assets) {
    if (!failedIds.has(a.id)) assetById[a.id] = a;
  }

  // `styleNames` (param) is Figma's style-id → name map for this subtree, so
  // every styleRef in simplified output can surface the designer's actual
  // name. This is the signal we use to map to existing repo tokens.

  // Per-node style references. Figma attaches a `styles` field to any node
  // that uses a style. We walk the raw tree once and collect these.
  const nodeStyleRefs = {};
  (function collectStyleRefs(n) {
    if (!n) return;
    if (n.styles) nodeStyleRefs[n.id] = n.styles;
    if (Array.isArray(n.children)) n.children.forEach(collectStyleRefs);
  })(rootNode);

  const compact = !args.verbose;
  const textStyleRegistry = { registry: {}, out: {} };
  const simplifyCtx = {
    assetById, opts, compact,
    keepIds: !!args.keepIds,
    styleNames, nodeStyleRefs,
    textStyles: compact ? textStyleRegistry : null,
    parentLayoutMode: 'NONE',
  };

  const output = {
    fileKey,
    fileName,
    screen: { id: rootNode.id, name: rootNode.name },
    generatedAt: new Date().toISOString(),
    assetCount: { icons: iconCount, images: imageCount },
  };
  output.layout = simplify(rootNode, simplifyCtx);

  // If we accumulated text styles during the walk, emit them as a top-level
  // map. Nodes reference them via `text.styleKey` — massively reduces size
  // on screens that use a handful of text styles across dozens of strings.
  if (compact && Object.keys(textStyleRegistry.out).length) {
    output.textStyles = textStyleRegistry.out;
  }
  if (screenRenderPath) {
    output.screenRender = screenRenderPath;
  }
  if (renderFailed.length || downloadErrors.length) {
    output.issues = {};
    if (renderFailed.length) output.issues.renderFailed = renderFailed;
    if (downloadErrors.length) output.issues.downloadFailed = downloadErrors;
  }

  await fs.writeFile(
    path.join(screenDir, 'screen.json'),
    JSON.stringify(output, null, 2),
  );
  if (args.fullJson) {
    await fs.writeFile(
      path.join(screenDir, 'raw.json'),
      JSON.stringify(rootNode, null, 2),
    );
  }

  console.log(`\n✔ done -> ${path.resolve(screenDir)}`);
  if (renderFailed.length) {
    console.log(`  note: ${renderFailed.length} nodes couldn't be rendered (see issues in screen.json)`);
  }
  return screenDir;
}

// Exports for testing — must be set before main() runs so tests can require this file
module.exports = {
  parseFigmaUrl,
  sanitize,
  uniquify,
  classifyNode,
  classifyTree,
  collectAssets,
  simplify,
  hasImageFill,
  hasExplicitExport,
  hasStructuredDescendants,
  extractRotation,
  chunk,
  framesToExport,
};

// Only run main() when invoked as a script, not when required for testing
if (require.main === module) {
  process.on('SIGINT', () => {
    console.error('\ninterrupted');
    process.exit(130);
  });

  main().catch(e => {
    console.error('ERROR:', e.message);
    if (process.env.DEBUG) console.error(e.stack);
    process.exit(1);
  });
}
