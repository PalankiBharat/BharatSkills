#!/usr/bin/env node
/**
 * detect-components.js
 *
 * Scan a screen.json and identify repeated component instances — nodes that
 * share a `componentId`. These are the high-value candidates for extracting
 * into shared @Composable functions instead of inlining their UI at each
 * call site.
 *
 * Output is a human-readable report plus a machine-readable JSON dump.
 *
 * Usage:
 *   node detect-components.js <screen.json> [more screen.json ...] [--json]
 *
 * Pass several screen.json files (every figma-out/<screen>/screen.json from
 * a batch export) to also detect components repeated ACROSS screens — the
 * single biggest source of duplicated composables in multi-screen flows.
 */

'use strict';

const fs = require('fs');

// ============================================================================
// CLI
// ============================================================================

function parseArgs(argv) {
  const args = { positional: [] };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--help' || a === '-h') args.help = true;
    else if (a === '--json') args.json = true;
    else if (a.startsWith('--')) args[a.slice(2)] = argv[++i];
    else args.positional.push(a);
  }
  return args;
}

function usage() {
  console.log(`Usage: node detect-components.js <screen.json> [more screen.json ...] [options]

Pass multiple screen.json files (e.g. figma-out/*/screen.json after a batch
export) to detect structures repeated across screens, not just within one.

Options:
  --json   Emit machine-readable JSON instead of the human report
  --help   Show this message
`);
}

// ============================================================================
// Walk
// ============================================================================

/**
 * Walk the tree and collect every INSTANCE node. Each entry carries the
 * breadcrumb path (root › parent › node) so the report is useful.
 */
function collectInstances(root, screenLabel) {
  const instances = [];
  function visit(node, trail) {
    if (!node) return;
    const here = [...trail, node.name || '(unnamed)'];
    if (node.type === 'INSTANCE' && node.componentId) {
      instances.push({
        id: node.id,
        name: node.name,
        componentId: node.componentId,
        path: here.join(' › '),
        screen: screenLabel || null,
        box: node.box,
      });
    }
    if (Array.isArray(node.children)) {
      for (const c of node.children) visit(c, here);
    }
  }
  visit(root, screenLabel ? [screenLabel] : []);
  return instances;
}

/**
 * Also flag non-INSTANCE nodes that SHOULD probably be components —
 * structurally identical subtrees recurring within a screen or across
 * screens.
 *
 * Method: Merkle-style subtree fingerprinting. Each node's fingerprint is a
 * hash of its canonical form — type, layout mode, style presence, asset
 * kind, text styleKey, size bucket — concatenated with the ORDERED
 * fingerprints of its visible children. Computed bottom-up in one O(n)
 * pass, so two subtrees share a fingerprint iff they are structurally
 * identical at EVERY depth, wherever (and on whichever screen) they appear.
 *
 * Deliberately EXCLUDED from the canonical form: text characters, exact
 * colours, and node names — a BookingCard with a different name and price
 * is still the same component. Sizes are bucketed to 16px so auto-layout
 * jitter doesn't split groups.
 */
function fnv1a(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, '0');
}

/**
 * Compute the fingerprint of a node (recursively fingerprinting children).
 * When `record` is provided, every visited node gets an entry
 * { fp, size } where size = number of nodes in the subtree.
 */
function fingerprintTree(node, record) {
  if (!node) return { fp: fnv1a('null'), size: 0 };
  const kids = (node.children || []).filter(c => c && c.visible !== false);
  const childResults = kids.map(c => fingerprintTree(c, record));
  const bucket = n => Math.round((n || 0) / 16) * 16;
  const canonical = [
    node.type || '?',
    node.layout && node.layout.mode ? node.layout.mode : 'NONE',
    node.asset ? (node.asset.kind || 'asset') : '',
    node.text && node.text.styleKey ? node.text.styleKey : (node.type === 'TEXT' ? 'text' : ''),
    node.radius != null ? 'r' : '',
    node.fill ? 'f' : '',
    node.stroke ? 's' : '',
    node.box ? `${bucket(node.box.w)}x${bucket(node.box.h)}` : '',
    childResults.map(r => r.fp).join('|'),
  ].join(';');
  const result = {
    fp: fnv1a(canonical),
    size: 1 + childResults.reduce((s, r) => s + r.size, 0),
  };
  if (record) record.push({ node, ...result });
  return result;
}

/**
 * Detect repeated structures across one or more screen roots.
 * `roots` is [{ root, screen }]; a bare node is accepted for compatibility.
 *
 * Reported when a container subtree of 3+ nodes repeats 3+ times within a
 * screen, or 2+ times spanning more than one screen (cross-screen repeats
 * are the duplicated-composable factory in batch flows, so the bar is
 * lower).
 */
function detectRepeatedStructures(roots) {
  const list = Array.isArray(roots) ? roots : [{ root: roots, screen: null }];

  // Pass 1: fingerprint every node, count candidate container subtrees.
  const isCandidate = (node, size) =>
    (node.type === 'FRAME' || node.type === 'GROUP' || node.type === 'COMPONENT') && size >= 3;
  const fpByNode = new Map();
  const counts = new Map();
  for (const { root } of list) {
    const record = [];
    fingerprintTree(root, record);
    for (const { node, fp, size } of record) {
      fpByNode.set(node, { fp, size });
      if (node === root || !isCandidate(node, size)) continue;
      counts.set(fp, (counts.get(fp) || 0) + 1);
    }
  }
  const qualifying = new Set([...counts.entries()].filter(([, n]) => n >= 2).map(([fp]) => fp));

  // Pass 2: walk top-down, recording only MAXIMAL repeated subtrees — once a
  // node is claimed by a qualifying fingerprint, its descendants are not
  // reported separately (a repeated card shouldn't also surface its inner
  // column as a second "component").
  const byFp = new Map();
  for (const { root, screen } of list) {
    (function walk(node) {
      if (!node) return;
      const meta = fpByNode.get(node);
      if (node !== root && meta && isCandidate(node, meta.size) && qualifying.has(meta.fp)) {
        if (!byFp.has(meta.fp)) byFp.set(meta.fp, []);
        byFp.get(meta.fp).push({ id: node.id, name: node.name, screen, size: meta.size });
        return; // claimed — don't descend
      }
      (node.children || []).forEach(walk);
    })(root);
  }

  return [...byFp.entries()]
    .map(([fp, arr]) => {
      const screens = [...new Set(arr.map(x => x.screen).filter(Boolean))];
      return {
        fingerprint: fp,
        count: arr.length,
        subtreeSize: arr[0].size,
        screens,
        crossScreen: screens.length > 1,
        suggestedComposableName: toComposableName(
          arr.map(x => x.name).find(n => n && !/^(frame|group|component)\s*\d*$/i.test(n)) || 'RepeatedBlock',
        ),
        examples: arr.slice(0, 5),
      };
    })
    .filter(g => (g.crossScreen ? g.count >= 2 : g.count >= 3))
    .sort((a, b) => (b.crossScreen - a.crossScreen) || (b.count * b.subtreeSize - a.count * a.subtreeSize));
}

// ============================================================================
// Grouping & naming
// ============================================================================

/**
 * Group instances by their componentId — each group becomes one shared
 * composable in the output code.
 */
function groupByComponent(instances) {
  const groups = new Map();
  for (const inst of instances) {
    if (!groups.has(inst.componentId)) {
      groups.set(inst.componentId, {
        componentId: inst.componentId,
        count: 0,
        names: new Set(),
        instances: [],
      });
    }
    const g = groups.get(inst.componentId);
    g.count++;
    if (inst.name) g.names.add(inst.name);
    g.instances.push(inst);
  }
  // Suggest a composable name for each group: use the most common instance name
  for (const g of groups.values()) {
    const nameFreq = new Map();
    for (const inst of g.instances) {
      const key = (inst.name || '').trim();
      if (key) nameFreq.set(key, (nameFreq.get(key) || 0) + 1);
    }
    const bestName = [...nameFreq.entries()]
      .sort((a, b) => b[1] - a[1])[0]?.[0] || 'Component';
    g.suggestedComposableName = toComposableName(bestName);
  }
  return [...groups.values()].sort((a, b) => b.count - a.count);
}

function toComposableName(raw) {
  if (!raw) return 'Component';
  // "my / cool_widget-thing" → "MyCoolWidgetThing"; "BookingCard" stays "BookingCard"
  const parts = String(raw)
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2') // split camelCase boundaries
    .replace(/[^A-Za-z0-9]+/g, ' ')
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (!parts.length) return 'Component';
  return parts.map(p => p[0].toUpperCase() + p.slice(1).toLowerCase()).join('');
}

// ============================================================================
// Reports
// ============================================================================

function humanReport(groups, repeatedShapes, totalInstances) {
  const lines = [];
  lines.push(`Found ${totalInstances} component instance(s) across ${groups.length} distinct component(s).`);
  lines.push('');

  if (!groups.length) {
    lines.push('No component instances found. Nothing to extract into shared composables.');
  } else {
    lines.push('Candidates for extraction (most-reused first):');
    lines.push('');
    for (const g of groups) {
      if (g.count < 2) continue; // Single-use components aren't high-value to extract
      lines.push(`  ${g.suggestedComposableName}  (used ${g.count}×)`);
      lines.push(`    componentId: ${g.componentId}`);
      const examplePaths = g.instances
        .slice(0, 3)
        .map(i => `      • ${i.path}`);
      lines.push(...examplePaths);
      if (g.instances.length > 3) {
        lines.push(`      …and ${g.instances.length - 3} more`);
      }
      lines.push('');
    }

    const singletons = groups.filter(g => g.count === 1);
    if (singletons.length) {
      lines.push(`${singletons.length} single-use component(s) — fine to inline:`);
      lines.push('  ' + singletons.map(g => g.suggestedComposableName).join(', '));
      lines.push('');
    }
  }

  if (repeatedShapes.length) {
    lines.push('Structurally identical subtrees NOT marked as components:');
    lines.push('(Worth extracting too — the designer may not have componentized them.)');
    lines.push('');
    for (const s of repeatedShapes) {
      const scope = s.crossScreen ? ` — ACROSS SCREENS: ${s.screens.join(', ')}` : '';
      lines.push(`  ${s.suggestedComposableName}  (${s.count}×, ${s.subtreeSize} nodes)${scope}`);
      for (const ex of s.examples) {
        lines.push(`    • ${ex.name || '(unnamed)'} [${ex.id}]${ex.screen ? ` (${ex.screen})` : ''}`);
      }
      lines.push('');
    }
  }

  return lines.join('\n');
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

  const path = require('path');
  const roots = [];
  const instances = [];
  for (const file of args.positional) {
    let input;
    try {
      input = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (e) {
      console.error(`Could not read ${file}: ${e.message}`);
      process.exit(1);
    }
    const root = input.layout || input;
    // Label by screen name (or parent dir) only when comparing multiple files
    const label = args.positional.length > 1
      ? (input.screen && input.screen.name) || path.basename(path.dirname(path.resolve(file)))
      : null;
    roots.push({ root, screen: label });
    instances.push(...collectInstances(root, label));
  }

  const groups = groupByComponent(instances);
  const repeatedShapes = detectRepeatedStructures(roots);

  if (args.json) {
    console.log(JSON.stringify({
      totalInstances: instances.length,
      groups: groups.map(g => ({
        componentId: g.componentId,
        count: g.count,
        suggestedComposableName: g.suggestedComposableName,
        instanceIds: g.instances.map(i => i.id),
      })),
      repeatedStructures: repeatedShapes,
    }, null, 2));
  } else {
    console.log(humanReport(groups, repeatedShapes, instances.length));
  }
}

if (require.main === module) {
  try { main(); }
  catch (e) { console.error('ERROR:', e.message); process.exit(1); }
}

module.exports = {
  collectInstances,
  groupByComponent,
  detectRepeatedStructures,
  fingerprintTree,
  toComposableName,
};
