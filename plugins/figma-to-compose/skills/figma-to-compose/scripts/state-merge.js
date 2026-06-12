'use strict';

// ============================================================================
// state-merge.js — merge multiple states of one component into ONE stateful
// composable. diffStates() finds the shared scaffold vs the per-state delta so
// codegen can emit `scaffold { when(state){ ...delta only... } }` — never a
// whole-tree duplication or alpha-blend hack. chooseApiShape() picks the Kotlin
// state API from the diff signals.
// ============================================================================

/**
 * Kotlin state API, by signal:
 *   sealed  — any state carries its own data (open has a list, closed doesn't)
 *   boolean — exactly two states, unnamed/binary, no per-state data
 *   enum    — named states (2-3) with no per-state data
 */
function chooseApiShape({ stateCount, named, perStateData }) {
  if (perStateData) return 'sealed';
  if (stateCount <= 2 && !named) return 'boolean';
  return 'enum';
}

/**
 * Match key for aligning nodes ACROSS states. Name-aware on purpose:
 * detect-components' structuralSignature omits node.name, so a Header and a List
 * (both childless FRAMEs) would collide. We key on name + type + box-bucket.
 */
function matchKey(node) {
  const bb = node.box || {};
  const w = bb.w ? Math.round(bb.w / 25) * 25 : 0;
  const h = bb.h ? Math.round(bb.h / 25) * 25 : 0;
  return `${node.name || '?'}|${node.type || '?'}|${w}x${h}`;
}

/**
 * states: [{ state, tree }]. Returns { shared:[key...], perState:{state:[key...]} }.
 * shared = children present in EVERY state (the scaffold); perState = each state's
 * children not in the shared set (the conditional delta).
 */
function diffStates(states) {
  const keySets = states.map(s => new Set((s.tree.children || []).map(matchKey)));
  const shared = [...keySets[0]].filter(k => keySets.every(set => set.has(k)));
  const sharedSet = new Set(shared);
  const perState = {};
  states.forEach((s, i) => {
    perState[s.state] = [...keySets[i]].filter(k => !sharedSet.has(k));
  });
  return { shared, perState };
}

module.exports = { chooseApiShape, matchKey, diffStates };
