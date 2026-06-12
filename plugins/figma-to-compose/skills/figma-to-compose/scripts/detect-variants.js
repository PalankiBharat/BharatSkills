#!/usr/bin/env node
/**
 * detect-variants.js
 *
 * Scan a screen.json for nodes whose names imply they're one variant of a
 * multi-state component (button default/pressed/disabled, checkbox
 * selected/unselected, etc.) when only that single variant is present in
 * the export.
 *
 * When the export is ambiguous, the right thing is to ASK the user rather
 * than invent the missing colours/styles — which is the specific failure
 * mode this script tries to surface.
 *
 * Usage:
 *   node detect-variants.js <path-to-screen.json> [--json]
 */

'use strict';

const fs = require('fs');

// ============================================================================
// State keyword vocabulary
// ============================================================================

// Words that appear in Figma variant names to denote a specific interaction
// state. When we see one of these in a node name, the node is probably
// ONE OF several visual variants the designer has — but the export only
// gives us the one.
const STATE_KEYWORDS = {
  button: [
    'default', 'idle', 'rest', 'normal', 'enabled', 'disabled',
    'hover', 'pressed', 'active', 'focused', 'focus', 'loading',
  ],
  selection: [
    'selected', 'unselected', 'checked', 'unchecked',
    'on', 'off', 'active', 'inactive',
  ],
  input: [
    'empty', 'filled', 'error', 'valid', 'focus', 'focused',
    'disabled', 'readonly',
  ],
};

const ALL_STATE_WORDS = new Set(
  Object.values(STATE_KEYWORDS).flat()
);

// Node-name patterns that suggest an interactive component (even without an
// explicit state keyword). A visible single-state export of these deserves
// a gentle reminder that the other states exist.
const INTERACTIVE_NAME_HINT = /\b(button|btn|cta|input|field|checkbox|radio|switch|toggle|chip|tab)\b/i;

// ============================================================================
// Walk
// ============================================================================

function* walk(node, depth = 0, trail = []) {
  if (!node) return;
  const here = [...trail, node.name || '(unnamed)'];
  yield { node, depth, path: here };
  if (Array.isArray(node.children)) {
    for (const c of node.children) yield* walk(c, depth + 1, here);
  }
}

function extractStateFromName(name) {
  if (!name) return null;
  // Split on separators commonly used in Figma variant naming.
  // "Button/Default", "Button=Default", "button-default", "button_default"
  const tokens = String(name).toLowerCase().split(/[\/=\-_\s,]+/).filter(Boolean);
  for (const tok of tokens) {
    if (ALL_STATE_WORDS.has(tok)) return tok;
  }
  return null;
}

/**
 * Group nodes that share the same structural role (by stripping the state
 * token from their names). Two nodes belong to the same variant family
 * if their "base name" (name minus the state token) matches.
 */
function groupByVariantFamily(nodesWithState) {
  const families = new Map();
  for (const entry of nodesWithState) {
    const base = (entry.node.name || '')
      .toLowerCase()
      .replace(new RegExp(`[\\/=\\-_\\s,]+(${[...ALL_STATE_WORDS].join('|')})\\b`, 'i'), '')
      .replace(new RegExp(`\\b(${[...ALL_STATE_WORDS].join('|')})[\\/=\\-_\\s,]+`, 'i'), '')
      .replace(/[\/=\-_\s,]+$/, '')
      .trim();
    if (!families.has(base)) families.set(base, []);
    families.get(base).push(entry);
  }
  return families;
}

// ============================================================================
// Detection
// ============================================================================

function detectVariants(screenJson) {
  const root = screenJson.layout || screenJson;
  const statefulNodes = [];
  const interactiveNoState = [];

  for (const entry of walk(root)) {
    const state = extractStateFromName(entry.node.name);
    if (state) {
      statefulNodes.push({ ...entry, state });
    } else if (INTERACTIVE_NAME_HINT.test(entry.node.name || '')) {
      interactiveNoState.push(entry);
    }
  }

  const families = groupByVariantFamily(statefulNodes);

  const singleStateFamilies = [];
  const multiStateFamilies = [];
  for (const [base, members] of families) {
    const states = new Set(members.map(m => m.state));
    const record = {
      baseName: base || '(unnamed)',
      states: [...states],
      members: members.map(m => ({
        id: m.node.id, name: m.node.name, path: m.path.join(' › '), state: m.state,
      })),
    };
    if (states.size === 1) singleStateFamilies.push(record);
    else multiStateFamilies.push(record);
  }

  return {
    singleStateFamilies,
    multiStateFamilies,
    interactiveWithoutState: interactiveNoState.map(e => ({
      id: e.node.id,
      name: e.node.name,
      path: e.path.join(' › '),
    })),
  };
}

// ============================================================================
// Reporting
// ============================================================================

function humanReport(detection) {
  const lines = [];
  const { singleStateFamilies, multiStateFamilies, interactiveWithoutState } = detection;

  if (!singleStateFamilies.length && !multiStateFamilies.length && !interactiveWithoutState.length) {
    lines.push('No variant ambiguity detected. Node names don\'t contain state keywords.');
    return lines.join('\n');
  }

  if (singleStateFamilies.length) {
    lines.push('⚠ AMBIGUOUS — these look like single-state exports of multi-state components:');
    lines.push('');
    lines.push('The node names contain a state keyword, but only that one state was exported.');
    lines.push('The other states (and their colors/styles) are NOT in this export.');
    lines.push('Ask the user for the missing states before generating code — do not invent colours.');
    lines.push('');
    for (const fam of singleStateFamilies) {
      lines.push(`  ${fam.baseName || '(unnamed family)'}`);
      lines.push(`    present state: ${fam.states.join(', ')}`);
      lines.push(`    likely missing: ${guessMissingStates(fam.states).join(', ') || '(depends on component type)'}`);
      for (const m of fam.members.slice(0, 3)) {
        lines.push(`      • ${m.path}`);
      }
      lines.push('');
    }
  }

  if (multiStateFamilies.length) {
    lines.push('✓ Multi-state families detected (all variants present in export):');
    lines.push('');
    for (const fam of multiStateFamilies) {
      lines.push(`  ${fam.baseName}: ${fam.states.join(', ')}`);
    }
    lines.push('');
    lines.push('For these, model the states in the generated code — typically an enum + when-branch.');
    lines.push('');
  }

  if (interactiveWithoutState.length) {
    lines.push('ℹ Interactive-looking nodes with no state keyword in the name:');
    lines.push('');
    lines.push('These may be fine (just a single-state component) but check with the user');
    lines.push('whether disabled/pressed/hover variants exist elsewhere in the file.');
    lines.push('');
    for (const n of interactiveWithoutState.slice(0, 5)) {
      lines.push(`  • ${n.path}`);
    }
    if (interactiveWithoutState.length > 5) {
      lines.push(`  …and ${interactiveWithoutState.length - 5} more`);
    }
  }

  return lines.join('\n');
}

function guessMissingStates(present) {
  const p = new Set(present);
  // If we have "default" or similar, interactive states are probably missing
  if (p.has('default') || p.has('idle') || p.has('rest') || p.has('normal') || p.has('enabled')) {
    return ['pressed', 'disabled', 'hover'];
  }
  if (p.has('disabled')) return ['enabled', 'pressed'];
  if (p.has('selected')) return ['unselected'];
  if (p.has('unselected')) return ['selected'];
  if (p.has('checked')) return ['unchecked'];
  if (p.has('empty')) return ['filled', 'error'];
  return [];
}

// ============================================================================
// CLI
// ============================================================================

function parseArgs(argv) {
  const args = { positional: [] };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--help' || a === '-h') args.help = true;
    else if (a === '--json') args.json = true;
    else args.positional.push(a);
  }
  return args;
}

function main() {
  const args = parseArgs(process.argv);
  if (args.help || !args.positional[0]) {
    console.log('Usage: node detect-variants.js <screen.json> [--json]');
    process.exit(args.help ? 0 : 1);
  }

  let input;
  try {
    input = JSON.parse(fs.readFileSync(args.positional[0], 'utf8'));
  } catch (e) {
    console.error(`Could not read ${args.positional[0]}: ${e.message}`);
    process.exit(2);
  }

  const detection = detectVariants(input);

  if (args.json) {
    console.log(JSON.stringify(detection, null, 2));
  } else {
    console.log(humanReport(detection));
  }

  // Exit non-zero when single-state ambiguity is found so the calling
  // script can decide to halt and ask the user.
  process.exit(detection.singleStateFamilies.length ? 1 : 0);
}

if (require.main === module) {
  try { main(); }
  catch (e) { console.error('ERROR:', e.message); process.exit(2); }
}

module.exports = {
  detectVariants,
  extractStateFromName,
  STATE_KEYWORDS,
  ALL_STATE_WORDS,
};
