const test = require('node:test');
const assert = require('node:assert');
const { chooseApiShape, diffStates, matchKey } = require('../scripts/state-merge');

test('2 binary states, no per-state data → boolean', () => {
  assert.equal(chooseApiShape({ stateCount: 2, named: false, perStateData: false }), 'boolean');
});
test('3 named states, no data → enum', () => {
  assert.equal(chooseApiShape({ stateCount: 3, named: true, perStateData: false }), 'enum');
});
test('states carry per-state data → sealed', () => {
  assert.equal(chooseApiShape({ stateCount: 2, named: true, perStateData: true }), 'sealed');
});

test('matchKey distinguishes by name (not just type) — Header != List', () => {
  const header = { name: 'Header', type: 'FRAME' };
  const list = { name: 'List', type: 'FRAME' };
  assert.notEqual(matchKey(header), matchKey(list));
});

test('diffStates separates shared scaffold from per-state delta', () => {
  const open = { state: 'open', tree: { children: [
    { name: 'Header', type: 'FRAME' },
    { name: 'List', type: 'FRAME' },
  ] } };
  const closed = { state: 'closed', tree: { children: [
    { name: 'Header', type: 'FRAME' },
  ] } };
  const d = diffStates([open, closed]);
  assert.equal(d.shared.length, 1);          // Header shared across both
  assert.equal(d.perState.open.length, 1);   // List only in open
  assert.equal(d.perState.closed.length, 0); // nothing extra in closed
});
