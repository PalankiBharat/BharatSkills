const test = require('node:test');
const assert = require('node:assert');
const { annotateCandidates } = require('../scripts/figma-outline');

// A container with two INSTANCEs of the same component (reused), a COMPONENT_SET,
// and a one-off frame.
const container = {
  id: '0:1', name: 'Sheet', type: 'FRAME', box: { w: 400, h: 600 },
  children: [
    { id: '0:2', name: 'RowA', type: 'INSTANCE', componentId: 'C:1', box: { w: 400, h: 56 } },
    { id: '0:3', name: 'RowB', type: 'INSTANCE', componentId: 'C:1', box: { w: 400, h: 56 } },
    { id: '0:4', name: 'Header', type: 'FRAME', box: { w: 400, h: 80 }, children: [] },
    { id: '0:5', name: 'Dropdown', type: 'COMPONENT_SET', box: { w: 400, h: 44 } },
  ],
};

test('reused INSTANCEs → role=instance with usedCount', () => {
  const byId = Object.fromEntries(annotateCandidates(container).map(c => [c.id, c]));
  assert.equal(byId['0:2'].role, 'instance');
  assert.equal(byId['0:2'].usedCount, 2);
  assert.equal(byId['0:2'].componentId, 'C:1');
});

test('one-off frame → role=one-off', () => {
  const byId = Object.fromEntries(annotateCandidates(container).map(c => [c.id, c]));
  assert.equal(byId['0:4'].role, 'one-off');
});

test('component set → role=component-set', () => {
  const byId = Object.fromEntries(annotateCandidates(container).map(c => [c.id, c]));
  assert.equal(byId['0:5'].role, 'component-set');
});

test('every candidate carries id, name, type, box', () => {
  for (const c of annotateCandidates(container)) {
    assert.ok(c.id && c.name && c.type);
    assert.ok('box' in c);
  }
});
