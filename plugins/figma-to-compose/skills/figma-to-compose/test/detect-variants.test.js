const test = require('node:test');
const assert = require('node:assert');
const { groupVariants } = require('../scripts/detect-variants');

test('nodes sharing componentSetId group as one variant set (authoritative)', () => {
  const nodes = [
    { id: '1', name: 'Dropdown/Open',   componentSetId: 'S:1' },
    { id: '2', name: 'Dropdown/Closed', componentSetId: 'S:1' },
    { id: '3', name: 'Unrelated',       componentSetId: null },
  ];
  const groups = groupVariants(nodes);
  assert.equal(groups.length, 1);
  assert.equal(groups[0].source, 'componentSetId');
  assert.deepEqual(groups[0].memberIds.sort(), ['1', '2']);
});

test('falls back to name heuristic when no componentSetId', () => {
  const nodes = [
    { id: '1', name: 'Chip State=Default', componentSetId: null },
    { id: '2', name: 'Chip State=Pressed', componentSetId: null },
  ];
  const groups = groupVariants(nodes);
  assert.equal(groups.length, 1);
  assert.equal(groups[0].source, 'name');
});

test('a single lone node is not a variant set (no false STOP)', () => {
  const nodes = [{ id: '1', name: 'Header', componentSetId: null }];
  assert.equal(groupVariants(nodes).length, 0);
});
