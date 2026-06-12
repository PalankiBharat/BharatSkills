const test = require('node:test');
const assert = require('node:assert');
const { parseFigmaUrl } = require('../scripts/figma-client');

test('single node-id, dash form normalised to colon', () => {
  const r = parseFigmaUrl('https://www.figma.com/design/ABC/Name?node-id=12-34');
  assert.equal(r.fileKey, 'ABC');
  assert.deepEqual(r.nodeIds, ['12:34']);
});

test('comma-separated node-ids are ALL returned (not just the first)', () => {
  const r = parseFigmaUrl('https://www.figma.com/design/ABC/Name?node-id=12-34,56-78');
  assert.deepEqual(r.nodeIds, ['12:34', '56:78']);
});

test('url-encoded colon form preserved', () => {
  const r = parseFigmaUrl('https://www.figma.com/design/ABC/Name?node-id=12%3A34');
  assert.deepEqual(r.nodeIds, ['12:34']);
});

test('no node-id yields empty nodeIds, not a crash', () => {
  const r = parseFigmaUrl('https://www.figma.com/design/ABC/Name');
  assert.equal(r.fileKey, 'ABC');
  assert.deepEqual(r.nodeIds, []);
});

test('community URL is rejected with a clear message', () => {
  assert.throws(
    () => parseFigmaUrl('https://www.figma.com/community/file/123/X'),
    /Community file URLs/,
  );
});
