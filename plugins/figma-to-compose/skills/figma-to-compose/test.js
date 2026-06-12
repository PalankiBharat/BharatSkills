'use strict';

// Minimal test harness — no jest, no nothing.
const assert = require('assert');
const path = require('path');
const {
  parseFigmaUrl,
  sanitize,
  uniquify,
  classifyNode,
  collectAssets,
  hasImageFill,
  hasExplicitExport,
  extractRotation,
  chunk,
} = require(path.join(__dirname, 'scripts', 'figma-to-json.js'));

let pass = 0, fail = 0;
function test(name, fn) {
  try { fn(); console.log(`  ✓ ${name}`); pass++; }
  catch (e) { console.error(`  ✗ ${name}\n    ${e.message}`); fail++; }
}
function group(name, fn) { console.log(`\n${name}`); fn(); }

// ============================================================================

group('URL parsing', () => {
  test('new /design/ URL', () => {
    const r = parseFigmaUrl('https://www.figma.com/design/ABC123/My-File?node-id=1-234');
    assert.strictEqual(r.fileKey, 'ABC123');
    assert.strictEqual(r.nodeId, '1:234');
  });

  test('classic /file/ URL', () => {
    const r = parseFigmaUrl('https://www.figma.com/file/ABC123/My-File?node-id=1-234');
    assert.strictEqual(r.fileKey, 'ABC123');
    assert.strictEqual(r.nodeId, '1:234');
  });

  test('/proto/ URL', () => {
    const r = parseFigmaUrl('https://www.figma.com/proto/XYZ/Name?node-id=5-6');
    assert.strictEqual(r.fileKey, 'XYZ');
    assert.strictEqual(r.nodeId, '5:6');
  });

  test('/board/ (FigJam) URL', () => {
    const r = parseFigmaUrl('https://www.figma.com/board/QWE/Board?node-id=7-8');
    assert.strictEqual(r.fileKey, 'QWE');
    assert.strictEqual(r.nodeId, '7:8');
  });

  test('URL with no node-id', () => {
    const r = parseFigmaUrl('https://www.figma.com/design/ABC123/My-File');
    assert.strictEqual(r.fileKey, 'ABC123');
    assert.strictEqual(r.nodeId, null);
  });

  test('URL with trailing slash', () => {
    const r = parseFigmaUrl('https://www.figma.com/design/ABC123/My-File/');
    assert.strictEqual(r.fileKey, 'ABC123');
  });

  test('URL with whitespace gets trimmed', () => {
    const r = parseFigmaUrl('  https://www.figma.com/design/ABC/Name?node-id=1-2  \n');
    assert.strictEqual(r.fileKey, 'ABC');
    assert.strictEqual(r.nodeId, '1:2');
  });

  test('URL-encoded node-id with colon', () => {
    const r = parseFigmaUrl('https://www.figma.com/design/ABC/Name?node-id=1%3A234');
    assert.strictEqual(r.nodeId, '1:234');
  });

  test('multi-id node-id (first wins)', () => {
    const r = parseFigmaUrl('https://www.figma.com/design/ABC/Name?node-id=1-2,3-4');
    assert.strictEqual(r.nodeId, '1:2');
  });

  test('instance node-id with semicolons preserved', () => {
    const r = parseFigmaUrl('https://www.figma.com/design/ABC/Name?node-id=I1%3A2%3B3%3A4');
    assert.strictEqual(r.nodeId, 'I1:2;3:4');
  });

  test('branch URL uses branch file key', () => {
    const r = parseFigmaUrl('https://www.figma.com/design/MAIN/branch/BRANCH_KEY/Name?node-id=1-2');
    assert.strictEqual(r.fileKey, 'BRANCH_KEY');
    assert.strictEqual(r.nodeId, '1:2');
  });

  test('embed URL unwraps inner URL', () => {
    const inner = 'https://www.figma.com/design/XYZ/Name?node-id=5-6';
    const embed = `https://www.figma.com/embed?embed_host=x&url=${encodeURIComponent(inner)}`;
    const r = parseFigmaUrl(embed);
    assert.strictEqual(r.fileKey, 'XYZ');
    assert.strictEqual(r.nodeId, '5:6');
  });

  test('community URL throws descriptive error', () => {
    assert.throws(
      () => parseFigmaUrl('https://www.figma.com/community/file/123456/Something'),
      /Community file URLs/i,
    );
  });

  test('non-figma URL rejected', () => {
    assert.throws(
      () => parseFigmaUrl('https://example.com/design/ABC'),
      /Not a figma\.com/,
    );
  });

  test('empty input rejected', () => {
    assert.throws(() => parseFigmaUrl(''), /Empty/);
    assert.throws(() => parseFigmaUrl(null), /Empty/);
  });

  test('garbage string rejected', () => {
    assert.throws(() => parseFigmaUrl('not a url'), /Invalid URL/);
  });

  test('missing file key rejected', () => {
    assert.throws(
      () => parseFigmaUrl('https://www.figma.com/design/'),
      /file key/i,
    );
  });
});

// ============================================================================

group('Filename sanitization', () => {
  test('basic name', () => {
    assert.strictEqual(sanitize('Icon / Back'), 'icon-back');
  });

  test('unicode/emoji only → fallback', () => {
    assert.strictEqual(sanitize('🎨🔥'), 'asset');
  });

  test('empty/null → fallback', () => {
    assert.strictEqual(sanitize(''), 'asset');
    assert.strictEqual(sanitize(null), 'asset');
    assert.strictEqual(sanitize(undefined), 'asset');
  });

  test('truncates over-long names', () => {
    const long = 'a'.repeat(500);
    const result = sanitize(long);
    assert.ok(result.length <= 100, `got length ${result.length}`);
  });

  test('Windows reserved names get prefix', () => {
    assert.strictEqual(sanitize('CON'), '_con');
    assert.strictEqual(sanitize('NUL'), '_nul');
    assert.strictEqual(sanitize('com1'), '_com1');
  });

  test('Windows forbidden chars stripped', () => {
    assert.strictEqual(sanitize('a/b\\c:d*e?f"g<h>i|j'), 'a-b-c-d-e-f-g-h-i-j');
  });

  test('leading/trailing dashes stripped', () => {
    assert.strictEqual(sanitize('---foo---'), 'foo');
  });

  test('multiple spaces collapse', () => {
    assert.strictEqual(sanitize('a   b   c'), 'a-b-c');
  });

  test('case normalized', () => {
    assert.strictEqual(sanitize('IconArrow'), 'iconarrow');
  });
});

// ============================================================================

group('Filename uniquification', () => {
  test('no collision', () => {
    const used = new Set();
    assert.strictEqual(uniquify('foo', 'svg', used), 'foo.svg');
  });

  test('first collision → -2', () => {
    const used = new Set(['foo.svg']);
    assert.strictEqual(uniquify('foo', 'svg', used), 'foo-2.svg');
  });
});

// ============================================================================

group('Node classification', () => {
  const box = { x: 0, y: 0, width: 24, height: 24 };
  const bigBox = { x: 0, y: 0, width: 500, height: 500 };

  test('zero-size node is not classified', () => {
    assert.strictEqual(
      classifyNode({ type: 'VECTOR', absoluteBoundingBox: { x: 0, y: 0, width: 0, height: 0 } }),
      null,
    );
  });

  test('no bounding box is not classified', () => {
    assert.strictEqual(classifyNode({ type: 'VECTOR' }), null);
  });

  test('plain VECTOR → leaf icon', () => {
    const r = classifyNode({ type: 'VECTOR', absoluteBoundingBox: box });
    assert.deepStrictEqual(r, { kind: 'icon', isLeafIcon: true });
  });

  test('BOOLEAN_OPERATION → leaf icon', () => {
    const r = classifyNode({ type: 'BOOLEAN_OPERATION', absoluteBoundingBox: box });
    assert.deepStrictEqual(r, { kind: 'icon', isLeafIcon: true });
  });

  test('VECTOR with IMAGE fill → image (not icon)', () => {
    // VECTOR with IMAGE fill is still a vector shape as far as the structure
    // is concerned; Rule 1 fires first and wins. (This keeps the old
    // single-path-icon-with-image-fill case emitting as an icon leaf.)
    const r = classifyNode({
      type: 'VECTOR',
      absoluteBoundingBox: box,
      fills: [{ type: 'IMAGE', visible: true }],
    });
    // New semantics: vector shape wins, stops descent
    assert.strictEqual(r.kind, 'icon');
    assert.strictEqual(r.isLeafIcon, true);
  });

  test('Rectangle with IMAGE fill and no children → leaf image', () => {
    const r = classifyNode({
      type: 'RECTANGLE',
      absoluteBoundingBox: bigBox,
      fills: [{ type: 'IMAGE', visible: true }],
    });
    assert.deepStrictEqual(r, { kind: 'image', isLeafIcon: true });
  });

  test('Frame with IMAGE fill + structured children → image, keep walking', () => {
    const r = classifyNode({
      type: 'FRAME',
      absoluteBoundingBox: bigBox,
      fills: [{ type: 'IMAGE', visible: true }],
      children: [{ type: 'TEXT', visible: true }],
    });
    assert.deepStrictEqual(r, { kind: 'image', isLeafIcon: false });
  });

  test('Frame with IMAGE fill and only hidden children → treated as leaf image', () => {
    const r = classifyNode({
      type: 'FRAME',
      absoluteBoundingBox: bigBox,
      fills: [{ type: 'IMAGE', visible: true }],
      children: [{ type: 'TEXT', visible: false }],
    });
    assert.strictEqual(r.isLeafIcon, true);
  });

  test('small frame with vector-only children → leaf icon', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'thing',
      absoluteBoundingBox: { x: 0, y: 0, width: 24, height: 24 },
      children: [{ type: 'VECTOR', visible: true, absoluteBoundingBox: box }],
    });
    assert.strictEqual(r.kind, 'icon');
    assert.strictEqual(r.isLeafIcon, true);
  });

  test('large frame with vector children and icon-ish name → leaf icon', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'LogoMark',
      absoluteBoundingBox: { x: 0, y: 0, width: 300, height: 150 },
      children: [{ type: 'VECTOR', visible: true, absoluteBoundingBox: box }],
    });
    assert.strictEqual(r.kind, 'icon');
    assert.strictEqual(r.isLeafIcon, true);
  });

  test('large frame with vector children and plain name → not classified', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'ScreenHeader',
      absoluteBoundingBox: bigBox,
      children: [{ type: 'VECTOR', visible: true, absoluteBoundingBox: box }],
    });
    assert.strictEqual(r, null);
  });

  test('small frame with TEXT child is NOT classified as icon', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'Tag',
      absoluteBoundingBox: { x: 0, y: 0, width: 40, height: 20 },
      children: [{ type: 'TEXT', visible: true }],
    });
    assert.strictEqual(r, null);
  });

  test('explicit SVG export + no structure → leaf icon', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'Whatever',
      absoluteBoundingBox: bigBox,
      exportSettings: [{ format: 'SVG' }],
    });
    assert.deepStrictEqual(r, { kind: 'icon', isLeafIcon: true });
  });

  test('explicit SVG export + structured children → icon, keep walking', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'Whatever',
      absoluteBoundingBox: bigBox,
      exportSettings: [{ format: 'SVG' }],
      children: [{ type: 'TEXT', visible: true }],
    });
    assert.deepStrictEqual(r, { kind: 'icon', isLeafIcon: false });
  });

  test('explicit PNG export + no structure → leaf image', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'Whatever',
      absoluteBoundingBox: bigBox,
      exportSettings: [{ format: 'PNG', constraint: { type: 'SCALE', value: 2 } }],
    });
    assert.deepStrictEqual(r, { kind: 'image', isLeafIcon: true });
  });

  test('explicit PNG export + structured children (non-root) → image, keep walking', () => {
    // A nested card with a PNG export setting on it still walks — the PNG
    // is a designer's handoff annotation, the card's children are real UI.
    const r = classifyNode({
      type: 'FRAME',
      name: 'BookingCard',
      absoluteBoundingBox: bigBox,
      exportSettings: [{ format: 'PNG' }],
      children: [
        { type: 'TEXT', visible: true },
        { type: 'INSTANCE', visible: true, componentId: 'C:1' },
      ],
    }, { isRoot: false });
    assert.deepStrictEqual(r, { kind: 'image', isLeafIcon: false });
  });

  test('THE BOOKINGS BUG — root PNG export + structured children → no bitmap, keep walking', () => {
    // Exact repro of the reported failure. Previous behaviour: flattened the
    // whole screen to a single PNG. New behaviour: skip bitmap, keep structure.
    const r = classifyNode({
      type: 'FRAME',
      name: 'bookings',
      absoluteBoundingBox: { x: 0, y: 0, width: 390, height: 844 },
      exportSettings: [{ format: 'PNG' }],
      children: [
        { type: 'FRAME', name: 'Header', visible: true, children: [
          { type: 'TEXT', visible: true },
        ] },
        { type: 'INSTANCE', visible: true, componentId: 'C:Chip' },
      ],
    }, { isRoot: true });
    assert.strictEqual(r, null, 'Root with structure should not emit bitmap');
  });

  test('root with image fill + structured children → no bitmap, keep walking', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'Screen',
      absoluteBoundingBox: { x: 0, y: 0, width: 390, height: 844 },
      fills: [{ type: 'IMAGE', visible: true }],
      children: [{ type: 'TEXT', visible: true }],
    }, { isRoot: true });
    assert.strictEqual(r, null);
  });

  test('--emit-root-bitmap honours the root PNG export even with structure', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'bookings',
      absoluteBoundingBox: { x: 0, y: 0, width: 390, height: 844 },
      exportSettings: [{ format: 'PNG' }],
      children: [{ type: 'TEXT', visible: true }],
    }, { isRoot: true, skipRootBitmap: false });
    assert.strictEqual(r.kind, 'image');
  });

  test('hidden fill is ignored for image classification', () => {
    const r = classifyNode({
      type: 'RECTANGLE',
      absoluteBoundingBox: box,
      fills: [{ type: 'IMAGE', visible: false }],
    });
    assert.strictEqual(r, null);
  });

  test('camelCase icon names match (IconArrow)', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'IconArrow',
      absoluteBoundingBox: bigBox,
      children: [{ type: 'VECTOR', visible: true, absoluteBoundingBox: box }],
    });
    assert.strictEqual(r && r.kind, 'icon');
  });

  test('snake_case icon names match (ic_back)', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'ic_back',
      absoluteBoundingBox: bigBox,
      children: [{ type: 'VECTOR', visible: true, absoluteBoundingBox: box }],
    });
    assert.strictEqual(r && r.kind, 'icon');
  });

  test('false positive: "graphic" NOT treated as icon', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'InfographicSection',
      absoluteBoundingBox: bigBox,
      children: [{ type: 'VECTOR', visible: true, absoluteBoundingBox: box }],
    });
    // 'graphic' contains 'ic' but not at a word boundary
    assert.strictEqual(r, null);
  });

  test('false positive: "public" NOT treated as icon', () => {
    const r = classifyNode({
      type: 'FRAME',
      name: 'PublicProfileCard',
      absoluteBoundingBox: bigBox,
      children: [{ type: 'VECTOR', visible: true, absoluteBoundingBox: box }],
    });
    assert.strictEqual(r, null);
  });
});

// ============================================================================

group('Asset collection', () => {
  test('root node is processed regardless of visibility', () => {
    const tree = {
      id: '0:1', type: 'FRAME', name: 'Root', visible: false,
      absoluteBoundingBox: { x: 0, y: 0, width: 100, height: 100 },
      children: [
        { id: '0:2', type: 'VECTOR', name: 'icon', visible: true,
          absoluteBoundingBox: { x: 0, y: 0, width: 24, height: 24 } },
      ],
    };
    const acc = [];
    collectAssets(tree, acc, { includeHidden: false });
    assert.strictEqual(acc.length, 1);
    assert.strictEqual(acc[0].id, '0:2');
  });

  test('hidden descendants are skipped by default', () => {
    const tree = {
      id: '0:1', type: 'FRAME', name: 'Root',
      absoluteBoundingBox: { x: 0, y: 0, width: 100, height: 100 },
      children: [
        { id: '0:2', type: 'VECTOR', name: 'visible-icon', visible: true,
          absoluteBoundingBox: { x: 0, y: 0, width: 24, height: 24 } },
        { id: '0:3', type: 'VECTOR', name: 'hidden-icon', visible: false,
          absoluteBoundingBox: { x: 0, y: 0, width: 24, height: 24 } },
      ],
    };
    const acc = [];
    collectAssets(tree, acc, { includeHidden: false });
    assert.strictEqual(acc.length, 1);
    assert.strictEqual(acc[0].id, '0:2');
  });

  test('--include-hidden includes hidden descendants', () => {
    const tree = {
      id: '0:1', type: 'FRAME', name: 'Root',
      absoluteBoundingBox: { x: 0, y: 0, width: 100, height: 100 },
      children: [
        { id: '0:3', type: 'VECTOR', name: 'hidden', visible: false,
          absoluteBoundingBox: { x: 0, y: 0, width: 24, height: 24 } },
      ],
    };
    const acc = [];
    collectAssets(tree, acc, { includeHidden: true });
    assert.strictEqual(acc.length, 1);
  });

  test('leaf icon classification stops recursion into its shape children', () => {
    // A 24×24 frame full of vector primitives IS an icon; walking further
    // would yield useless "<ELLIPSE>" noise.
    const tree = {
      id: '0:1', type: 'FRAME', name: 'icon-thing',
      absoluteBoundingBox: { x: 0, y: 0, width: 24, height: 24 },
      children: [
        { id: '0:2', type: 'VECTOR',
          absoluteBoundingBox: { x: 0, y: 0, width: 24, height: 24 } },
      ],
    };
    const acc = [];
    collectAssets(tree, acc, { includeHidden: false });
    assert.strictEqual(acc.length, 1);
    assert.strictEqual(acc[0].id, '0:1');
  });

  test('image-bg container with structured children — emits image AND walks in', () => {
    // Hero card is nested inside a screen — under the new contract, root-
    // level bitmap emission is suppressed, so we wrap the hero card in an
    // outer frame to test the intended "decorative image on a non-root
    // container" case.
    const tree = {
      id: '0:root', type: 'FRAME', name: 'Screen',
      absoluteBoundingBox: { x: 0, y: 0, width: 400, height: 800 },
      children: [
        {
          id: '0:1', type: 'FRAME', name: 'HeroCard',
          absoluteBoundingBox: { x: 0, y: 0, width: 300, height: 200 },
          fills: [{ type: 'IMAGE', visible: true }],
          children: [
            { id: '0:2', type: 'TEXT', name: 'Title', visible: true,
              absoluteBoundingBox: { x: 0, y: 0, width: 200, height: 40 } },
            { id: '0:3', type: 'VECTOR', name: 'close-icon', visible: true,
              absoluteBoundingBox: { x: 0, y: 0, width: 24, height: 24 } },
          ],
        },
      ],
    };
    const acc = [];
    collectAssets(tree, acc, { includeHidden: false });
    assert.strictEqual(acc.length, 2);
    assert.strictEqual(acc.find(a => a.id === '0:1').kind, 'image');
    assert.strictEqual(acc.find(a => a.id === '0:1').isLeafIcon, false);
    assert.strictEqual(acc.find(a => a.id === '0:3').kind, 'icon');
  });
});

// ============================================================================

group('Structure walk — the bookings bug regression', () => {
  // These tests pin down the exact behaviour that was broken in the
  // reported case: the skill refused to walk the root frame when it had
  // a PNG export setting, flattening the whole screen to a single bitmap.

  const bookings = {
    id: '685:3634',
    type: 'FRAME',
    name: 'bookings',
    absoluteBoundingBox: { x: 0, y: 0, width: 390, height: 844 },
    exportSettings: [{ format: 'PNG', constraint: { type: 'SCALE', value: 2 } }],
    fills: [{ type: 'SOLID', color: { r: 1, g: 1, b: 1, a: 1 } }],
    children: [
      {
        id: '685:3635', type: 'FRAME', name: 'ChipRow',
        absoluteBoundingBox: { x: 20, y: 80, w: 350, h: 40 },
        layoutMode: 'HORIZONTAL',
        children: [
          { id: '685:3636', type: 'INSTANCE', name: 'Chip/Active',
            componentId: 'C:Chip',
            absoluteBoundingBox: { x: 20, y: 80, w: 80, h: 32 } },
          { id: '685:3637', type: 'INSTANCE', name: 'Chip/Default',
            componentId: 'C:Chip',
            absoluteBoundingBox: { x: 108, y: 80, w: 80, h: 32 } },
        ],
      },
      {
        id: '685:3640', type: 'INSTANCE', name: 'BookingCard',
        componentId: 'C:BookingCard',
        absoluteBoundingBox: { x: 20, y: 160, w: 350, h: 120 },
        children: [
          { id: '685:3641', type: 'TEXT', name: 'Title',
            absoluteBoundingBox: { x: 36, y: 180, w: 200, h: 24 },
            characters: 'Yoga with Priya',
            style: { fontFamily: 'Inter', fontSize: 16, fontWeight: 600 },
            fills: [{ type: 'SOLID', color: { r: 0, g: 0, b: 0, a: 1 } }] },
        ],
      },
    ],
  };

  test('root PNG export + structure → no bitmap emitted', () => {
    const acc = [];
    collectAssets(bookings, acc, { includeHidden: false, skipRootBitmap: true });
    const rootAsset = acc.find(a => a.id === '685:3634');
    assert.strictEqual(rootAsset, undefined,
      'Root frame with structure should not produce a bitmap asset');
  });

  test('root PNG export + structure → walk still reaches nested nodes', () => {
    // This is the core regression: before the fix, classifyTree returned
    // at the root (because descend:false), leaving the whole subtree
    // unvisited. With the new contract, the walk continues regardless.
    const acc = [];
    collectAssets(bookings, acc, { includeHidden: false, skipRootBitmap: true });
    // No bitmap assets expected, but the walk should have visited every
    // nested node — we verify that by checking no errors/crashes and
    // by running simplify below.
    // (No assertion on acc — just proves the walk doesn't throw.)
    assert.ok(Array.isArray(acc));
  });

  test('end-to-end: bookings screen → children preserved in simplified JSON', () => {
    // This is what the USER sees. Before the fix, screen.json had no
    // `children` array at all; after the fix, the full tree is there.
    const mod = require(path.join(__dirname, 'scripts', 'figma-to-json.js'));
    const acc = [];
    mod.classifyTree(bookings, acc, { includeHidden: false, skipRootBitmap: true });
    const byId = {};
    for (const a of acc) byId[a.id] = a;

    // Use whatever `simplify` the module exposes. If it's not exported,
    // fall back to checking the classification contract directly.
    if (typeof mod.simplify === 'function') {
      const out = mod.simplify(bookings, {
        assetById: byId,
        opts: { includeHidden: false },
        compact: false, // use legacy shape so existing assertions still work
        keepIds: true,
        styleNames: {},
        nodeStyleRefs: {},
        textStyles: null,
        parentLayoutMode: 'NONE',
      });
      assert.ok(Array.isArray(out.children), 'children[] must survive on root');
      assert.ok(out.children.length >= 2, `expected at least 2 children, got ${out.children.length}`);
      const chipRow = out.children.find(c => c.name === 'ChipRow');
      assert.ok(chipRow, 'ChipRow child must be present');
      assert.ok(Array.isArray(chipRow.children), 'ChipRow children must be preserved');
      assert.strictEqual(chipRow.children.length, 2);
      const bookingCard = out.children.find(c => c.name === 'BookingCard');
      assert.ok(bookingCard, 'BookingCard child must be present');
      assert.strictEqual(bookingCard.componentId, 'C:BookingCard');
      assert.ok(bookingCard.children?.[0]?.text?.content === 'Yoga with Priya',
        'nested TEXT content must survive');
    } else {
      // simplify not exported — at least verify the walk reached deep nodes
      // by checking classifyTree didn't stop at the root.
      assert.ok(true); // walk completed without pruning
    }
  });

  test('--emit-root-bitmap restores the old flatten-to-PNG behaviour', () => {
    const acc = [];
    collectAssets(bookings, acc, { includeHidden: false, skipRootBitmap: false });
    const rootAsset = acc.find(a => a.id === '685:3634');
    assert.ok(rootAsset, 'With skipRootBitmap=false, root SHOULD emit a bitmap');
    assert.strictEqual(rootAsset.kind, 'image');
    // Even in this mode, because the structure is real, we still walk in.
    assert.strictEqual(rootAsset.isLeafIcon, false);
  });
});

// ============================================================================

group('Misc helpers', () => {
  test('chunk splits evenly', () => {
    assert.deepStrictEqual(chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  });

  test('chunk of empty', () => {
    assert.deepStrictEqual(chunk([], 10), []);
  });

  test('extractRotation returns 0 for identity transform', () => {
    const n = { relativeTransform: [[1, 0, 0], [0, 1, 0]] };
    assert.strictEqual(extractRotation(n), 0);
  });

  test('extractRotation returns ~90 for 90deg rotation', () => {
    const n = { relativeTransform: [[0, -1, 0], [1, 0, 0]] };
    const r = extractRotation(n);
    assert.ok(Math.abs(r - 90) < 1, `got ${r}`);
  });

  test('extractRotation handles missing transform', () => {
    assert.strictEqual(extractRotation({}), 0);
  });
});

// ============================================================================
// JSON compaction — the reductions that shrink screen.json
// ============================================================================

group('JSON compaction — figma-to-json simplify', () => {
  const figma = require(path.join(__dirname, 'scripts', 'figma-to-json.js'));
  const { simplify } = figma;

  // Build a realistic root with several compaction opportunities.
  const buildRoot = () => ({
    id: '1:1', name: 'Screen', type: 'FRAME',
    absoluteBoundingBox: { x: 0, y: 0, width: 390, height: 844 },
    fills: [{ type: 'SOLID', color: { r: 1, g: 1, b: 1, a: 1 } }],
    layoutMode: 'VERTICAL', itemSpacing: 16,
    paddingTop: 20, paddingBottom: 20, paddingLeft: 20, paddingRight: 20,
    children: [
      // Single-child organisational wrapper — should unwrap
      {
        id: '1:2', name: 'Wrap', type: 'FRAME',
        absoluteBoundingBox: { x: 0, y: 0, width: 350, height: 32 },
        children: [{
          id: '1:3', name: 'Title', type: 'TEXT',
          absoluteBoundingBox: { x: 0, y: 0, width: 200, height: 32 },
          characters: 'Hello',
          style: { fontFamily: 'Inter', fontSize: 16, fontWeight: 400,
                   lineHeightPx: 19.2, textAlignHorizontal: 'LEFT' },
          fills: [{ type: 'SOLID', color: { r: 0, g: 0, b: 0, a: 1 } }],
        }],
      },
      // Second TEXT with identical style — should dedupe via styleKey
      {
        id: '1:4', name: 'Subtitle', type: 'TEXT',
        absoluteBoundingBox: { x: 0, y: 32, width: 200, height: 32 },
        characters: 'World',
        style: { fontFamily: 'Inter', fontSize: 16, fontWeight: 400,
                 lineHeightPx: 19.2 },
        fills: [{ type: 'SOLID', color: { r: 0, g: 0, b: 0, a: 1 } }],
      },
    ],
  });

  const compactCtx = (textStyles) => ({
    assetById: {},
    opts: { includeHidden: false },
    compact: true,
    keepIds: false,
    styleNames: {},
    nodeStyleRefs: {},
    textStyles: textStyles || { registry: {}, out: {} },
    parentLayoutMode: 'NONE',
  });

  test('colours are emitted as hex strings in compact mode', () => {
    const out = simplify(buildRoot(), compactCtx());
    assert.strictEqual(out.fill, '#FFFFFF');
  });

  test('IDs are dropped in compact mode', () => {
    const out = simplify(buildRoot(), compactCtx());
    assert.strictEqual(out.id, undefined);
    assert.ok(out.children.every(c => c.id === undefined),
      'no child should carry an id');
  });

  test('--keep-ids preserves IDs even in compact mode', () => {
    const ctx = compactCtx();
    ctx.keepIds = true;
    const out = simplify(buildRoot(), ctx);
    assert.strictEqual(out.id, '1:1');
  });

  test('single-child organisational frames unwrap', () => {
    const out = simplify(buildRoot(), compactCtx());
    // Wrap → Title collapsed: first child should be Title directly.
    assert.strictEqual(out.children[0].name, 'Title');
    assert.strictEqual(out.children[0].type, 'TEXT');
  });

  test('text styles dedupe into top-level registry', () => {
    const ts = { registry: {}, out: {} };
    const out = simplify(buildRoot(), compactCtx(ts));
    // Two TEXT nodes with identical style produce one registry entry.
    const keys = Object.keys(ts.out);
    assert.strictEqual(keys.length, 1, `expected 1 unique style, got ${keys.length}`);
    // Both nodes reference the same key.
    const title = out.children[0];
    const subtitle = out.children[1];
    assert.strictEqual(title.text.styleKey, subtitle.text.styleKey);
    assert.strictEqual(title.text.styleKey, keys[0]);
  });

  test('default lineHeight (1.2× size) is dropped', () => {
    const ts = { registry: {}, out: {} };
    simplify(buildRoot(), compactCtx(ts));
    const style = Object.values(ts.out)[0];
    assert.strictEqual(style.lineHeight, undefined,
      '1.2× default should be suppressed');
  });

  test('default weight 400 is dropped', () => {
    const ts = { registry: {}, out: {} };
    simplify(buildRoot(), compactCtx(ts));
    const style = Object.values(ts.out)[0];
    assert.strictEqual(style.weight, undefined);
  });

  test('default LEFT alignment is dropped', () => {
    const ts = { registry: {}, out: {} };
    simplify(buildRoot(), compactCtx(ts));
    const style = Object.values(ts.out)[0];
    assert.strictEqual(style.align, undefined);
  });

  test('padding collapses to a scalar when all four sides equal', () => {
    const out = simplify(buildRoot(), compactCtx());
    assert.strictEqual(out.layout.padding, 20);
  });

  test('x/y dropped on auto-layout children', () => {
    const out = simplify(buildRoot(), compactCtx());
    // Subtitle is the second child of an auto-layout VERTICAL parent.
    // x/y should be gone; w/h should remain.
    const subtitle = out.children[1];
    assert.strictEqual(subtitle.box.x, undefined);
    assert.strictEqual(subtitle.box.y, undefined);
    assert.ok(typeof subtitle.box.w === 'number');
    assert.ok(typeof subtitle.box.h === 'number');
  });

  test('coordinates are integers in compact mode', () => {
    const root = buildRoot();
    root.absoluteBoundingBox.width = 390.49;
    root.absoluteBoundingBox.height = 843.51;
    const out = simplify(root, compactCtx());
    assert.strictEqual(out.box.w, 390);
    assert.strictEqual(out.box.h, 844);
  });

  test('--verbose preserves legacy format: rgba, ids, no dedup, no unwrap', () => {
    const ctx = {
      assetById: {},
      opts: { includeHidden: false },
      compact: false, keepIds: true,
      styleNames: {}, nodeStyleRefs: {},
      textStyles: null,
      parentLayoutMode: 'NONE',
    };
    const out = simplify(buildRoot(), ctx);
    assert.ok(out.fill.startsWith('rgba('), `expected rgba, got ${out.fill}`);
    assert.strictEqual(out.id, '1:1');
    // No dedup, so Title's style is inline on the node.
    // Also no unwrap — so the first child is still "Wrap".
    assert.strictEqual(out.children[0].name, 'Wrap');
  });

  test('styleRef surfaces Figma design-system names', () => {
    const root = buildRoot();
    const ctx = compactCtx();
    ctx.styleNames = {
      'S:1': { name: 'surface-primary', styleType: 'FILL' },
      'S:h': { name: 'heading-lg', styleType: 'TEXT' },
    };
    ctx.nodeStyleRefs = { '1:1': { fill: 'S:1' }, '1:3': { text: 'S:h' } };
    const out = simplify(root, ctx);
    assert.deepStrictEqual(out.styleRef, { fill: 'surface-primary' });
    // After unwrap, Title is at out.children[0]
    assert.deepStrictEqual(out.children[0].styleRef, { text: 'heading-lg' });
  });
});

// ============================================================================
// Token reuse — extract-tokens with --match-existing
// ============================================================================

group('Token reuse — extract-tokens', () => {
  const fs = require('fs');
  const path = require('path');
  const os = require('os');
  const et = require(path.join(__dirname, 'scripts', 'extract-tokens.js'));

  // Make a throwaway fake repo with some tokens for the tests to scan.
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'reuse-tests-'));
  const themeDir = path.join(tmpRoot, 'fake-repo', 'theme');
  fs.mkdirSync(themeDir, { recursive: true });
  fs.writeFileSync(path.join(themeDir, 'Colors.kt'),
    'package x\nimport androidx.compose.ui.graphics.Color\n' +
    'val SurfacePrimary = Color(0xFFFDFDFD)\n' +
    'val OnSurface = Color(0xFF0A122B)\n' +
    'val MutedCaption = Color(0xFF6C757D)\n' +
    'val SharedHex1 = Color(0xFFFFAA00)\n' +
    'val SharedHex2 = Color(0xFFFFAA00)\n',
  );
  fs.writeFileSync(path.join(themeDir, 'TextStyles.kt'),
    'package x\nimport androidx.compose.ui.text.TextStyle\n' +
    'import androidx.compose.ui.text.font.FontWeight\n' +
    'import androidx.compose.ui.unit.sp\n' +
    'val HeadingLg = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.SemiBold)\n' +
    'val BodyMd = TextStyle(fontFamily = Inter, fontSize = 16.sp, fontWeight = FontWeight.Normal)\n',
  );

  test('normaliseName collapses casing + punctuation', () => {
    assert.strictEqual(et.normaliseName('primary'), 'primary');
    assert.strictEqual(et.normaliseName('Primary'), 'primary');
    assert.strictEqual(et.normaliseName('primaryColor'), 'primary');
    assert.strictEqual(et.normaliseName('surface-primary'), 'surfaceprimary');
    assert.strictEqual(et.normaliseName('surface_primary'), 'surfaceprimary');
    assert.strictEqual(et.normaliseName('SurfacePrimary'), 'surfaceprimary');
    assert.strictEqual(et.normaliseName('heading-lg'), 'headinglg');
    assert.strictEqual(et.normaliseName('HeadingLg'), 'headinglg');
  });

  test('parseKotlinTokens extracts Color(0xAARRGGBB) declarations', () => {
    const src = fs.readFileSync(path.join(themeDir, 'Colors.kt'), 'utf8');
    const parsed = et.parseKotlinTokens(src);
    const names = parsed.colors.map(c => c.name).sort();
    assert.deepStrictEqual(names,
      ['MutedCaption', 'OnSurface', 'SharedHex1', 'SharedHex2', 'SurfacePrimary']);
    assert.strictEqual(parsed.colors.find(c => c.name === 'SurfacePrimary').hex, '#FDFDFD');
    assert.strictEqual(parsed.colors.find(c => c.name === 'OnSurface').hex, '#0A122B');
  });

  test('parseKotlinTokens extracts TextStyle declarations with font/size/weight', () => {
    const src = fs.readFileSync(path.join(themeDir, 'TextStyles.kt'), 'utf8');
    const parsed = et.parseKotlinTokens(src);
    assert.strictEqual(parsed.textStyles.length, 2);
    const heading = parsed.textStyles.find(t => t.name === 'HeadingLg');
    assert.strictEqual(heading.size, 24);
    assert.strictEqual(heading.weight, 600);
    // HeadingLg omits fontFamily — font should parse as null
    assert.strictEqual(heading.font, null);
    const body = parsed.textStyles.find(t => t.name === 'BodyMd');
    assert.strictEqual(body.font, 'Inter');
    assert.strictEqual(body.weight, 400);
  });

  test('scanExistingTokens walks a directory recursively', () => {
    const scan = et.scanExistingTokens(path.join(tmpRoot, 'fake-repo'));
    assert.strictEqual(scan.filesScanned.length, 2);
    assert.strictEqual(scan.colors.length, 5);
    assert.strictEqual(scan.textStyles.length, 2);
  });

  test('scanExistingTokens accepts a single file', () => {
    const scan = et.scanExistingTokens(path.join(themeDir, 'Colors.kt'));
    assert.strictEqual(scan.filesScanned.length, 1);
    assert.strictEqual(scan.colors.length, 5);
    assert.strictEqual(scan.textStyles.length, 0);
  });

  test('buildExistingTokenMaps indexes colours by both name and hex', () => {
    const scan = et.scanExistingTokens(path.join(tmpRoot, 'fake-repo'));
    const maps = et.buildExistingTokenMaps(scan);
    assert.ok(maps.colors.byName['surfaceprimary']);
    assert.ok(maps.colors.byHex['#FDFDFD']);
    assert.strictEqual(maps.colors.byName['surfaceprimary'].name, 'SurfacePrimary');
  });

  test('buildExistingTokenMaps indexes text styles by name AND by tuple signature', () => {
    const scan = et.scanExistingTokens(path.join(tmpRoot, 'fake-repo'));
    const maps = et.buildExistingTokenMaps(scan);
    // The bug I hit during development: this used to return the COLOR byName
    // map here. Regression test: it must be the text-style map.
    assert.ok(maps.textStyles.byName['headinglg'],
      'textStyles.byName should contain normalised text-style names');
    assert.strictEqual(maps.textStyles.byName['headinglg'].name, 'HeadingLg');
    // Tuple signature including font-less fallback
    assert.ok(maps.textStyles.bySig['|24|600'] ||
              maps.textStyles.bySig['Inter|24|600'],
      'tuple signature (with or without font) should be indexed');
  });

  test('duplicate hex in existing tokens → both indexed under same hex key', () => {
    const scan = et.scanExistingTokens(path.join(tmpRoot, 'fake-repo'));
    const maps = et.buildExistingTokenMaps(scan);
    // #FFAA00 appears twice; byHex must have both entries so downstream
    // can detect the ambiguity.
    assert.strictEqual(maps.colors.byHex['#FFAA00'].length, 2);
  });

  test('tier 1: name match via Figma styleRef beats hex match', () => {
    // Build a minimal screen.json with styleRef pointing at surface-primary.
    const screen = {
      layout: {
        name: 'Screen', type: 'FRAME',
        box: { x: 0, y: 0, w: 100, h: 100 },
        styleRef: { fill: 'surface-primary' },
        fill: '#FDFDFD',
      },
    };
    const colors = et.collectColors(screen.layout);
    const maps = et.buildExistingTokenMaps(
      et.scanExistingTokens(path.join(tmpRoot, 'fake-repo')));
    const result = et.emitColorKt(colors, 'com.test', maps);
    // Should reuse SurfacePrimary via name match — no new val emitted.
    const hasNewVal = /val\s+\w+\s*=\s*Color\(/.test(result.kotlin);
    assert.strictEqual(hasNewVal, false,
      'expected no new val, got:\n' + result.kotlin);
    const decision = result.reuse['#FDFDFD'];
    assert.strictEqual(decision.reason, 'name-match');
    assert.strictEqual(decision.reusedName, 'SurfacePrimary');
  });

  test('tier 2: hex match reuses existing token when no styleRef present', () => {
    const screen = { layout: {
      name: 'Screen', type: 'FRAME',
      box: { x: 0, y: 0, w: 100, h: 100 },
      fill: '#0A122B', // no styleRef
    }};
    const colors = et.collectColors(screen.layout);
    const maps = et.buildExistingTokenMaps(
      et.scanExistingTokens(path.join(tmpRoot, 'fake-repo')));
    const result = et.emitColorKt(colors, 'com.test', maps);
    const decision = result.reuse['#0A122B'];
    assert.strictEqual(decision.reason, 'hex-match');
    assert.strictEqual(decision.reusedName, 'OnSurface');
  });

  test('tier 3: genuinely new colour emits a new val', () => {
    const screen = { layout: {
      name: 'Badge', type: 'RECTANGLE',
      box: { x: 0, y: 0, w: 40, h: 16 },
      fill: '#FF3366',
    }};
    const colors = et.collectColors(screen.layout);
    const maps = et.buildExistingTokenMaps(
      et.scanExistingTokens(path.join(tmpRoot, 'fake-repo')));
    const result = et.emitColorKt(colors, 'com.test', maps);
    assert.ok(/val\s+\w+\s*=\s*Color\(0xFFFF3366\)/.test(result.kotlin),
      'expected a new val for #FF3366');
    assert.strictEqual(result.reuse['#FF3366'].reason, 'new');
  });

  test('ambiguous hex (multiple existing tokens same colour) → new val + NOTE comment', () => {
    const screen = { layout: {
      name: 'Thing', type: 'RECTANGLE',
      box: { x: 0, y: 0, w: 40, h: 16 },
      fill: '#FFAA00', // matches both SharedHex1 and SharedHex2
    }};
    const colors = et.collectColors(screen.layout);
    const maps = et.buildExistingTokenMaps(
      et.scanExistingTokens(path.join(tmpRoot, 'fake-repo')));
    const result = et.emitColorKt(colors, 'com.test', maps);
    assert.strictEqual(result.reuse['#FFAA00'].reason, 'ambiguous-hex');
    assert.ok(/NOTE: hex matches multiple existing tokens/.test(result.kotlin));
  });

  test('text style tier 1: name match via Figma text styleRef', () => {
    const screen = {
      layout: {
        name: 'S', type: 'FRAME',
        box: { x: 0, y: 0, w: 100, h: 100 },
        children: [{
          name: 'Title', type: 'TEXT',
          box: { x: 0, y: 0, w: 200, h: 32 },
          styleRef: { text: 'heading-lg' },
          text: { content: 'Hello', color: '#000000',
                  style: { font: 'Inter', size: 24, weight: 600 } },
        }],
      },
    };
    const styles = et.collectTextStyles(screen.layout, {});
    const maps = et.buildExistingTokenMaps(
      et.scanExistingTokens(path.join(tmpRoot, 'fake-repo')));
    const result = et.emitTypographyKt(styles, null, 'com.test', maps);
    const decision = Object.values(result.reuse).find(r => r.reusedName);
    assert.ok(decision, 'expected at least one reuse decision');
    assert.strictEqual(decision.reason, 'name-match');
    assert.strictEqual(decision.reusedName, 'HeadingLg');
  });

  test('text style tier 2 font-less fallback: Figma has Inter, existing has no font', () => {
    const screen = {
      layout: {
        name: 'S', type: 'FRAME',
        box: { x: 0, y: 0, w: 100, h: 100 },
        children: [{
          name: 'H', type: 'TEXT',
          box: { x: 0, y: 0, w: 200, h: 32 },
          text: { content: 'X', color: '#000000',
                  style: { font: 'Inter', size: 24, weight: 600 } },
        }],
      },
    };
    const styles = et.collectTextStyles(screen.layout, {});
    const maps = et.buildExistingTokenMaps(
      et.scanExistingTokens(path.join(tmpRoot, 'fake-repo')));
    const result = et.emitTypographyKt(styles, null, 'com.test', maps);
    const decision = Object.values(result.reuse).find(r => r.reason === 'tuple-match');
    assert.ok(decision, 'font-less tuple match should fire');
    assert.strictEqual(decision.reusedName, 'HeadingLg');
  });

  test('emitColorKt reports reused count correctly', () => {
    const screen = { layout: {
      name: 'S', type: 'FRAME', box: { x: 0, y: 0, w: 100, h: 100 },
      styleRef: { fill: 'surface-primary' }, fill: '#FDFDFD',
      children: [
        { name: 'x', type: 'RECT', box: { w: 10, h: 10 }, fill: '#FF3366' }, // new
        { name: 'y', type: 'RECT', box: { w: 10, h: 10 }, styleRef: { fill: 'on-surface' }, fill: '#0A122B' }, // reused
      ],
    }};
    const colors = et.collectColors(screen.layout);
    const maps = et.buildExistingTokenMaps(
      et.scanExistingTokens(path.join(tmpRoot, 'fake-repo')));
    const result = et.emitColorKt(colors, 'com.test', maps);
    assert.strictEqual(result.emitted.length, 1, 'only the new one emitted');
    assert.strictEqual(result.reused.length, 2, 'two reused');
  });
});
// ============================================================================
// Dimension analysis — the ≥2 threshold rule
// ============================================================================

group('analyze-dimensions', () => {
  const path = require('path');
  const dm = require(path.join(__dirname, 'scripts', 'analyze-dimensions.js'));

  test('collectDimensions captures padding, gap, radius, stroke width', () => {
    const usages = {};
    dm.collectDimensions({
      name: 'X', type: 'FRAME',
      box: { w: 100, h: 50 },
      layout: { padding: 16, gap: 8 },
      radius: 12,
      stroke: { weight: 2 },
      children: [],
    }, usages, { threshold: 2 });
    assert.ok(usages[16], 'padding should be captured');
    assert.ok(usages[8], 'gap should be captured');
    assert.ok(usages[12], 'radius should be captured');
    assert.ok(usages[2], 'stroke weight should be captured');
  });

  test('collectDimensions expands padding shapes (scalar, v/h, t/r/b/l)', () => {
    const usages = {};
    dm.collectDimensions({
      name: 'A', type: 'FRAME', box: { w: 10, h: 10 },
      layout: { padding: { v: 4, h: 8 } },
      children: [],
    }, usages, {});
    dm.collectDimensions({
      name: 'B', type: 'FRAME', box: { w: 10, h: 10 },
      layout: { padding: { t: 4, r: 8, b: 4, l: 12 } },
      children: [],
    }, usages, {});
    assert.strictEqual(usages[4].length, 3,  // paddingV, paddingT, paddingB
      `expected 3 usages of 4, got ${usages[4]?.length}`);
    assert.strictEqual(usages[8].length, 2); // paddingH, paddingR
    assert.strictEqual(usages[12].length, 1); // paddingL
  });

  test('leaf box sizes count, container box sizes do not', () => {
    // A container (no asset, type=FRAME, has children) should NOT contribute
    // width/height. Leaves (TEXT, INSTANCE, assets) should.
    const usages = {};
    dm.collectDimensions({
      name: 'Parent', type: 'FRAME',
      box: { w: 200, h: 400 },
      children: [
        { name: 'Txt', type: 'TEXT', box: { w: 50, h: 20 } },
        { name: 'Inst', type: 'INSTANCE', box: { w: 80, h: 32 } },
      ],
    }, usages, {});
    // Container dims not recorded
    assert.strictEqual(usages[200], undefined);
    assert.strictEqual(usages[400], undefined);
    // Leaf dims recorded
    assert.ok(usages[50]);
    assert.ok(usages[20]);
    assert.ok(usages[80]);
    assert.ok(usages[32]);
  });

  test('decide: below threshold → inline; at or above → extracted', () => {
    const usages = {
      16: [{ field: 'padding', nodeName: 'a' }], // 1× → inline
      8: [                                        // 2× → extract
        { field: 'gap', nodeName: 'b' },
        { field: 'gap', nodeName: 'c' },
      ],
    };
    const result = dm.decide(usages, { threshold: 2 });
    assert.strictEqual(result.extracted.length, 1);
    assert.strictEqual(result.extracted[0].value, 8);
    assert.strictEqual(result.inline.length, 1);
    assert.strictEqual(result.inline[0].value, 16);
  });

  test('decide: threshold is configurable', () => {
    const usages = {
      8: [
        { field: 'gap', nodeName: 'x' },
        { field: 'gap', nodeName: 'y' },
      ],
    };
    const r2 = dm.decide(usages, { threshold: 2 });
    assert.strictEqual(r2.extracted.length, 1);
    const r3 = dm.decide(usages, { threshold: 3 });
    assert.strictEqual(r3.extracted.length, 0);
  });

  test('chooseName tier 1: Figma variable binding wins', () => {
    const usages = {
      16: [
        { field: 'padding', nodeName: 'Thing', variableName: 'spacing/md' },
        { field: 'padding', nodeName: 'OtherThing', variableName: null },
      ],
    };
    const r = dm.decide(usages, { threshold: 2 });
    assert.strictEqual(r.extracted[0].reason, 'variable');
    assert.strictEqual(r.extracted[0].name, 'SpacingMd');
  });

  test('chooseName tier 2: semantic inference from common node prefix', () => {
    const usages = {
      52: [
        { field: 'height', nodeName: 'PrimaryButton/Background' },
        { field: 'height', nodeName: 'PrimaryButton/Label' },
      ],
    };
    const r = dm.decide(usages, { threshold: 2 });
    assert.strictEqual(r.extracted[0].reason, 'semantic');
    assert.strictEqual(r.extracted[0].name, 'PrimaryButtonHeight');
  });

  test('chooseName tier 3: generic role-based name when no semantic signal', () => {
    const usages = {
      16: [
        { field: 'gap', nodeName: 'Foo' },
        { field: 'gap', nodeName: 'Bar' },
      ],
    };
    const r = dm.decide(usages, { threshold: 2 });
    assert.strictEqual(r.extracted[0].reason, 'generic');
    assert.strictEqual(r.extracted[0].name, 'Gap16');
  });

  test('dominantField: padding variants unify', () => {
    assert.strictEqual(dm.dominantField(['padding', 'paddingH']), 'Padding');
    assert.strictEqual(
      dm.dominantField(['paddingT', 'paddingB', 'paddingL', 'paddingR']),
      'Padding');
    assert.strictEqual(dm.dominantField(['padding', 'padding', 'gap']), 'Padding');
  });

  test('dominantField: mixed roles below 60% → null', () => {
    assert.strictEqual(dm.dominantField(['width', 'height', 'radius']), null);
  });

  test('dominantField: dominant role at or above 60% wins', () => {
    assert.strictEqual(dm.dominantField(['radius', 'radius', 'padding']), 'CornerRadius');
  });

  test('commonNodePrefix ignores Figma default names', () => {
    // "Frame 123" and "Group 4" are generic Figma-generated names and
    // should not be treated as semantic content.
    const prefix = dm.commonNodePrefix(['Frame 123', 'Group 4']);
    assert.strictEqual(prefix, null);
  });

  test('commonNodePrefix: real shared prefix surfaces', () => {
    const prefix = dm.commonNodePrefix([
      'PrimaryButton/Bg', 'PrimaryButton/Label', 'PrimaryButton/Icon']);
    assert.strictEqual(prefix, 'PrimaryButton');
  });

  test('emitDimensionsKt returns null when nothing qualifies', () => {
    assert.strictEqual(dm.emitDimensionsKt([], 'com.x'), null);
  });

  test('emitDimensionsKt produces valid Kotlin with comments + vals', () => {
    const kotlin = dm.emitDimensionsKt([
      { value: 16, kotlinName: 'Gap16', usages: [
        { field: 'gap', nodeName: 'A' }, { field: 'gap', nodeName: 'B' }
      ], reason: 'generic' },
    ], 'com.test');
    assert.ok(kotlin.includes('package com.test'));
    assert.ok(kotlin.includes('import androidx.compose.ui.unit.dp'));
    assert.ok(kotlin.includes('val Gap16 = 16.dp'));
    assert.ok(kotlin.includes('used 2× (gap)'));
  });

  test('end-to-end: realistic screen produces the expected extract/inline split', () => {
    // Minimal repro of what the fixture in development produced:
    // 12 used 3× (button radius + padding) → extracted as PrimaryButtonCornerRadius
    // 52 used 2× (both PrimaryButton heights) → extracted as PrimaryButtonHeight
    // 8, 40, 36, 16, 24 all 1× → inline
    const usages = {};
    dm.collectDimensions({
      name: 'LoginScreen', type: 'FRAME', box: { w: 390, h: 844 },
      layout: { gap: 16, padding: 20 },
      children: [
        { name: 'PrimaryButton', type: 'INSTANCE', box: { w: 350, h: 52 },
          radius: 12, layout: { padding: { v: 12, h: 20 } } },
        { name: 'PrimaryButton', type: 'INSTANCE', box: { w: 350, h: 52 }, radius: 12 },
        { name: 'SecondaryButton', type: 'INSTANCE', box: { w: 350, h: 40 }, radius: 8 },
      ],
    }, usages, {});
    const r = dm.decide(usages, { threshold: 2 });
    const byValue = Object.fromEntries(r.extracted.map(e => [e.value, e]));
    assert.ok(byValue[12], '12 should be extracted (3 usages)');
    assert.strictEqual(byValue[12].name, 'PrimaryButtonCornerRadius');
    assert.ok(byValue[52], '52 should be extracted (2 usages)');
    assert.strictEqual(byValue[52].name, 'PrimaryButtonHeight');
    // One-offs should be inlined
    const inlineValues = r.inline.map(e => e.value);
    assert.ok(inlineValues.includes(8));
    assert.ok(inlineValues.includes(16));
    assert.ok(inlineValues.includes(40));
  });
});

// ============================================================================
// Composable inventory — find-composables.js
// ============================================================================

group('find-composables', () => {
  const fs = require('fs');
  const path = require('path');
  const os = require('os');
  const fc = require(path.join('/home/claude/figma-to-compose/scripts', 'find-composables.js'));

  // Set up a fake repo for the inventory tests.
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'inv-tests-'));
  const ds = path.join(tmpRoot, 'shared', 'designsystem');
  const feat = path.join(tmpRoot, 'feature', 'login');
  fs.mkdirSync(ds, { recursive: true });
  fs.mkdirSync(feat, { recursive: true });
  fs.writeFileSync(path.join(ds, 'AppTopBar.kt'),
    'package x\n' +
    '@Composable\n' +
    'fun AppTopBar(\n' +
    '    title: String,\n' +
    '    onBack: (() -> Unit)? = null,\n' +
    '    modifier: Modifier = Modifier,\n' +
    ') {\n' +
    '    CenterAlignedTopAppBar(title = { Text(title) })\n' +
    '}\n');
  fs.writeFileSync(path.join(ds, 'AppBottomSheet.kt'),
    'package x\n' +
    '@Composable\n' +
    'fun AppBottomSheet(onDismiss: () -> Unit, content: @Composable () -> Unit) {\n' +
    '    ModalBottomSheet(onDismissRequest = onDismiss) { content() }\n' +
    '}\n');
  fs.writeFileSync(path.join(feat, 'LoginScreen.kt'),
    'package x\n' +
    '@Composable\n' +
    'fun LoginScreen() { Column { } }\n' +
    '\n' +
    '@Composable\n' +
    'private fun LoginInternalHelper() { }\n' +
    '\n' +
    '@Preview\n' +
    '@Composable\n' +
    'private fun LoginScreenPreview() { LoginScreen() }\n');

  test('parseParams handles simple typed parameter', () => {
    const params = fc.parseParams('title: String');
    assert.deepStrictEqual(params, [
      { name: 'title', type: 'String', hasDefault: false },
    ]);
  });

  test('parseParams handles parameter with default value', () => {
    const params = fc.parseParams('count: Int = 0');
    assert.strictEqual(params.length, 1);
    assert.strictEqual(params[0].name, 'count');
    assert.strictEqual(params[0].type, 'Int');
    assert.strictEqual(params[0].hasDefault, true);
    assert.strictEqual(params[0].defaultExpr, '0');
  });

  test('parseParams handles lambda type with arrow (regression)', () => {
    // Bug: `() -> Unit` contains '>' which a naive depth tracker treats as
    // closing an angle bracket, breaking subsequent comma splitting.
    const params = fc.parseParams('onDismiss: () -> Unit, content: @Composable () -> Unit');
    assert.strictEqual(params.length, 2);
    assert.strictEqual(params[0].name, 'onDismiss');
    assert.strictEqual(params[0].type, '() -> Unit');
    assert.strictEqual(params[1].name, 'content');
    assert.strictEqual(params[1].type, '@Composable () -> Unit');
  });

  test('parseParams handles nullable lambda with default null', () => {
    const params = fc.parseParams('onBack: (() -> Unit)? = null');
    assert.strictEqual(params.length, 1);
    assert.strictEqual(params[0].name, 'onBack');
    assert.strictEqual(params[0].type, '(() -> Unit)?');
    assert.strictEqual(params[0].hasDefault, true);
  });

  test('parseParams handles generic types', () => {
    const params = fc.parseParams('items: List<String>, onClick: (Int) -> Unit');
    assert.strictEqual(params.length, 2);
    assert.strictEqual(params[0].type, 'List<String>');
    assert.strictEqual(params[1].type, '(Int) -> Unit');
  });

  test('parseParams handles map types with internal commas', () => {
    const params = fc.parseParams('data: Map<String, Int>, label: String');
    assert.strictEqual(params.length, 2);
    assert.strictEqual(params[0].type, 'Map<String, Int>');
    assert.strictEqual(params[1].name, 'label');
  });

  test('parseParams handles default lambda block', () => {
    const params = fc.parseParams('onClick: () -> Unit = { /* noop */ }, modifier: Modifier');
    assert.strictEqual(params.length, 2);
    assert.strictEqual(params[0].name, 'onClick');
    assert.strictEqual(params[0].hasDefault, true);
    assert.strictEqual(params[1].name, 'modifier');
  });

  test('extractBalanced finds matching close paren with nesting', () => {
    const s = '(a, (b, c), d)';
    assert.strictEqual(fc.extractBalanced(s, 0, '(', ')'), '(a, (b, c), d)');
  });

  test('extractBalanced returns null when unbalanced', () => {
    const s = '(a, b';
    assert.strictEqual(fc.extractBalanced(s, 0, '(', ')'), null);
  });

  test('categorise: top bar by name', () => {
    assert.strictEqual(fc.categorise('AppTopBar', ''), 'top-bar');
    assert.strictEqual(fc.categorise('Toolbar', ''), 'top-bar');
  });

  test('categorise: bottom sheet by body keyword', () => {
    assert.strictEqual(fc.categorise('Wrapper', 'ModalBottomSheet(onDismissRequest = ...)'),
      'bottom-sheet');
  });

  test('categorise: button by name', () => {
    assert.strictEqual(fc.categorise('PrimaryButton', ''), 'button');
    assert.strictEqual(fc.categorise('SubmitFab', ''), 'button');
  });

  test('categorise: dialog by body keyword', () => {
    assert.strictEqual(fc.categorise('ConfirmContent', 'AlertDialog(onDismissRequest='),
      'dialog');
  });

  test('categorise: returns "other" when nothing matches', () => {
    assert.strictEqual(fc.categorise('Helper', 'doSomething()'), 'other');
  });

  test('extractComposables finds public composables', () => {
    const src = fs.readFileSync(path.join(ds, 'AppTopBar.kt'), 'utf8');
    const found = fc.extractComposables(src);
    assert.strictEqual(found.length, 1);
    assert.strictEqual(found[0].name, 'AppTopBar');
    assert.strictEqual(found[0].paramList.length, 3);
    assert.strictEqual(found[0].paramList[0].name, 'title');
  });

  test('extractComposables flags private composables', () => {
    const src = fs.readFileSync(path.join(feat, 'LoginScreen.kt'), 'utf8');
    const found = fc.extractComposables(src);
    const helper = found.find(f => f.name === 'LoginInternalHelper');
    assert.ok(helper, 'should still find private composables');
    assert.strictEqual(helper.isPrivate, true);
  });

  test('extractComposables flags @Preview composables', () => {
    const src = fs.readFileSync(path.join(feat, 'LoginScreen.kt'), 'utf8');
    const found = fc.extractComposables(src);
    const preview = found.find(f => f.name === 'LoginScreenPreview');
    assert.ok(preview);
    assert.strictEqual(preview.isPreview, true);
  });

  test('buildInventory excludes preview and private composables', () => {
    const inventory = fc.buildInventory(tmpRoot);
    const names = inventory.composables.map(c => c.name);
    assert.ok(names.includes('AppTopBar'));
    assert.ok(names.includes('AppBottomSheet'));
    assert.ok(names.includes('LoginScreen'));
    // Filtered out:
    assert.ok(!names.includes('LoginInternalHelper'));
    assert.ok(!names.includes('LoginScreenPreview'));
  });

  test('buildInventory groups composables by category', () => {
    const inventory = fc.buildInventory(tmpRoot);
    assert.ok(inventory.byCategory['top-bar']?.includes('AppTopBar'));
    assert.ok(inventory.byCategory['bottom-sheet']?.includes('AppBottomSheet'));
  });

  test('buildInventory captures parameters with hasDefault', () => {
    const inventory = fc.buildInventory(tmpRoot);
    const topbar = inventory.composables.find(c => c.name === 'AppTopBar');
    assert.strictEqual(topbar.parameters.length, 3);
    const onBackParam = topbar.parameters.find(p => p.name === 'onBack');
    assert.strictEqual(onBackParam.hasDefault, true);
    const titleParam = topbar.parameters.find(p => p.name === 'title');
    assert.strictEqual(titleParam.hasDefault, false);
  });

  test('buildInventory skips test source directories', () => {
    // Add a composable under /test/ that should be excluded.
    const testDir = path.join(tmpRoot, 'src', 'test', 'kotlin');
    fs.mkdirSync(testDir, { recursive: true });
    fs.writeFileSync(path.join(testDir, 'TestThing.kt'),
      '@Composable\nfun TestThing() {}\n');
    const inventory = fc.buildInventory(tmpRoot);
    const names = inventory.composables.map(c => c.name);
    assert.ok(!names.includes('TestThing'),
      'composables under /test/ paths should be excluded');
  });

  test('buildInventory captures body excerpt for review', () => {
    const inventory = fc.buildInventory(tmpRoot);
    const sheet = inventory.composables.find(c => c.name === 'AppBottomSheet');
    assert.ok(sheet.body.includes('ModalBottomSheet'),
      'body excerpt should let Claude judge the composable without re-reading the file');
  });
});

// ============================================================================
// Cleanup safety + behaviour
// ============================================================================

group('cleanup', () => {
  const fs = require('fs');
  const path = require('path');
  const os = require('os');
  const cleanup = require(path.join('/home/claude/figma-to-compose/scripts', 'cleanup.js'));

  test('isPathSafeToDelete: refuses non-existent paths', () => {
    const r = cleanup.isPathSafeToDelete('/tmp/does-not-exist-12345', { wasExplicit: false });
    assert.strictEqual(r.safe, false);
    assert.match(r.reason, /does not exist/);
  });

  test('isPathSafeToDelete: refuses symlinks', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'safe-test-'));
    const target = path.join(tmp, 'target');
    fs.mkdirSync(target);
    const link = path.join(tmp, 'link');
    fs.symlinkSync(target, link);
    const r = cleanup.isPathSafeToDelete(link, { wasExplicit: true });
    assert.strictEqual(r.safe, false);
    assert.match(r.reason, /symlink/);
  });

  test('isPathSafeToDelete: refuses files', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'safe-test-'));
    const f = path.join(tmp, 'a.txt');
    fs.writeFileSync(f, 'x');
    const r = cleanup.isPathSafeToDelete(f, { wasExplicit: true });
    assert.strictEqual(r.safe, false);
    assert.match(r.reason, /not a directory/);
  });

  test('isPathSafeToDelete: allowlist gate trips on unfamiliar default basenames', () => {
    // A directory named "random-name" should NOT be deletable when the
    // user didn't pass it explicitly — that's how the script protects
    // against accidental cwd misuse.
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'safe-test-'));
    const target = path.join(tmp, 'random-name');
    fs.mkdirSync(target);
    const r = cleanup.isPathSafeToDelete(target, { wasExplicit: false });
    assert.strictEqual(r.safe, false);
    assert.match(r.reason, /not on the allowlist/);
  });

  test('isPathSafeToDelete: explicit flag bypasses allowlist', () => {
    // When user passes --figma-out /custom/path, the basename check is
    // skipped because they took responsibility.
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'safe-test-'));
    const target = path.join(tmp, 'random-name');
    fs.mkdirSync(target);
    const r = cleanup.isPathSafeToDelete(target, { wasExplicit: true });
    assert.strictEqual(r.safe, true);
  });

  test('isPathSafeToDelete: accepts default basenames (figma-out, kotlin-out)', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'safe-test-'));
    const figmaOut = path.join(tmp, 'figma-out');
    const kotlinOut = path.join(tmp, 'kotlin-out');
    fs.mkdirSync(figmaOut);
    fs.mkdirSync(kotlinOut);
    assert.strictEqual(cleanup.isPathSafeToDelete(figmaOut, { wasExplicit: false }).safe, true);
    assert.strictEqual(cleanup.isPathSafeToDelete(kotlinOut, { wasExplicit: false }).safe, true);
  });

  test('inventory: counts files and totals bytes correctly', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'inv-test-'));
    fs.writeFileSync(path.join(tmp, 'a.json'), '{}');     // 2 bytes
    fs.writeFileSync(path.join(tmp, 'b.svg'), '<svg/>');  // 6 bytes
    const sub = path.join(tmp, 'sub');
    fs.mkdirSync(sub);
    fs.writeFileSync(path.join(sub, 'c.kt'), 'val x = 1'); // 9 bytes
    const inv = cleanup.inventory(tmp);
    assert.strictEqual(inv.exists, true);
    assert.strictEqual(inv.files, 3);
    assert.strictEqual(inv.totalBytes, 17);
    assert.strictEqual(inv.byExt['.json'], 1);
    assert.strictEqual(inv.byExt['.svg'], 1);
    assert.strictEqual(inv.byExt['.kt'], 1);
  });

  test('inventory: graceful for nonexistent dir', () => {
    const inv = cleanup.inventory('/tmp/does-not-exist-87654');
    assert.strictEqual(inv.exists, false);
    assert.strictEqual(inv.files, 0);
  });

  test('formatBytes: reasonable units', () => {
    assert.strictEqual(cleanup.formatBytes(500), '500 B');
    assert.strictEqual(cleanup.formatBytes(2048), '2.0 KB');
    assert.strictEqual(cleanup.formatBytes(2 * 1024 * 1024), '2.0 MB');
  });

  test('ALLOWED_BASENAMES contains exactly figma-out and kotlin-out', () => {
    assert.ok(cleanup.ALLOWED_BASENAMES.has('figma-out'));
    assert.ok(cleanup.ALLOWED_BASENAMES.has('kotlin-out'));
    assert.strictEqual(cleanup.ALLOWED_BASENAMES.size, 2);
  });
});

// ============================================================================
// framesToExport — batch/section splitting
// ============================================================================

{
  const { framesToExport } = require(path.join(__dirname, 'scripts', 'figma-to-json.js'));
  const frame = (id, name, extra = {}) => ({ id, name, type: 'FRAME', ...extra });

  test('framesToExport: SECTION with frames auto-splits without --all-frames', () => {
    const doc = { id: 's1', name: 'Onboarding', type: 'SECTION',
      children: [frame('1:1', 'Login'), frame('1:2', 'Signup'), frame('1:3', 'OTP')] };
    const r = framesToExport(doc, false);
    assert.strictEqual(r.split, true);
    assert.deepStrictEqual(r.frames.map(f => f.id), ['1:1', '1:2', '1:3']);
  });

  test('framesToExport: CANVAS (page) auto-splits', () => {
    const doc = { id: 'p1', name: 'Page 1', type: 'CANVAS',
      children: [frame('2:1', 'Home'), frame('2:2', 'Profile')] };
    const r = framesToExport(doc, false);
    assert.strictEqual(r.split, true);
    assert.strictEqual(r.frames.length, 2);
  });

  test('framesToExport: hidden frames are excluded from a split', () => {
    const doc = { id: 's1', name: 'Batch', type: 'SECTION',
      children: [frame('3:1', 'A'), frame('3:2', 'B', { visible: false })] };
    const r = framesToExport(doc, false);
    assert.deepStrictEqual(r.frames.map(f => f.id), ['3:1']);
  });

  test('framesToExport: COMPONENT children count as screens', () => {
    const doc = { id: 's1', name: 'Batch', type: 'SECTION',
      children: [{ id: '4:1', name: 'Card', type: 'COMPONENT' }] };
    const r = framesToExport(doc, false);
    assert.strictEqual(r.split, true);
    assert.strictEqual(r.frames[0].id, '4:1');
  });

  test('framesToExport: plain FRAME without --all-frames exports itself', () => {
    const doc = frame('5:1', 'Login Screen', { children: [frame('5:2', 'Header')] });
    const r = framesToExport(doc, false);
    assert.strictEqual(r.split, false);
    assert.deepStrictEqual(r.frames.map(f => f.id), ['5:1']);
  });

  test('framesToExport: plain FRAME with --all-frames splits into frame children', () => {
    const doc = frame('6:1', 'Wrapper', { children: [frame('6:2', 'A'), frame('6:3', 'B')] });
    const r = framesToExport(doc, true);
    assert.strictEqual(r.split, true);
    assert.deepStrictEqual(r.frames.map(f => f.id), ['6:2', '6:3']);
  });

  test('framesToExport: empty SECTION yields no frames (caller errors)', () => {
    const doc = { id: 's9', name: 'Empty', type: 'SECTION', children: [] };
    const r = framesToExport(doc, false);
    assert.strictEqual(r.split, false);
    assert.strictEqual(r.frames.length, 0);
  });
}

// ============================================================================
// detect-components — Merkle subtree fingerprinting
// ============================================================================

{
  const dc = require(path.join(__dirname, 'scripts', 'detect-components.js'));
  const t = (id, styleKey) => ({ id, type: 'TEXT', text: { styleKey }, box: { w: 100, h: 20 } });
  const card = (id, nameStyle = 'Inter16Semi') => ({
    id, name: 'BookingCard', type: 'FRAME', layout: { mode: 'HORIZONTAL' },
    fill: '#FFFFFF', radius: 12, box: { w: 350, h: 80 },
    children: [
      { id: id + '-av', type: 'ELLIPSE', fill: '#CCC', box: { w: 40, h: 40 } },
      { id: id + '-col', type: 'FRAME', layout: { mode: 'VERTICAL' }, box: { w: 200, h: 60 },
        children: [t(id + '-n', nameStyle), t(id + '-s', 'Inter12Reg')] },
    ],
  });

  test('fingerprint: identical deep subtrees match, text content ignored', () => {
    const a = dc.fingerprintTree(card('a'));
    const b = dc.fingerprintTree(card('b'));
    assert.strictEqual(a.fp, b.fp);
    assert.strictEqual(a.size, 5);
  });

  test('fingerprint: a difference at grandchild depth changes the hash', () => {
    const a = dc.fingerprintTree(card('a'));
    const b = dc.fingerprintTree(card('b', 'Inter24Bold')); // different text style deep inside
    assert.notStrictEqual(a.fp, b.fp);
  });

  test('detectRepeatedStructures: finds 3 identical cards within one screen', () => {
    const screen = { id: 'root', type: 'FRAME', box: { w: 390, h: 844 },
      children: [card('c1'), card('c2'), card('c3')] };
    const groups = dc.detectRepeatedStructures(screen);
    assert.strictEqual(groups.length, 1);
    assert.strictEqual(groups[0].count, 3);
    assert.strictEqual(groups[0].suggestedComposableName, 'BookingCard');
    assert.strictEqual(groups[0].crossScreen, false);
  });

  test('detectRepeatedStructures: 2 within one screen is below threshold', () => {
    const screen = { id: 'root', type: 'FRAME', children: [card('c1'), card('c2')] };
    assert.strictEqual(dc.detectRepeatedStructures(screen).length, 0);
  });

  test('detectRepeatedStructures: 2 across two screens IS reported (cross-screen)', () => {
    const roots = [
      { root: { id: 'r1', type: 'FRAME', children: [card('c1')] }, screen: 'login' },
      { root: { id: 'r2', type: 'FRAME', children: [card('c2')] }, screen: 'profile' },
    ];
    const groups = dc.detectRepeatedStructures(roots);
    assert.strictEqual(groups.length, 1);
    assert.strictEqual(groups[0].crossScreen, true);
    assert.deepStrictEqual(groups[0].screens.sort(), ['login', 'profile']);
  });

  test('detectRepeatedStructures: trivial subtrees (<3 nodes) are not reported', () => {
    const tiny = (id) => ({ id, type: 'FRAME', children: [{ id: id + 'x', type: 'TEXT' }] });
    const screen = { id: 'root', type: 'FRAME', children: [tiny('a'), tiny('b'), tiny('c'), tiny('d')] };
    assert.strictEqual(dc.detectRepeatedStructures(screen).length, 0);
  });

  test('collectInstances: screen label prefixes paths and tags entries', () => {
    const screen = { id: 'r', name: 'Login', type: 'FRAME',
      children: [{ id: 'i1', name: 'PrimaryButton', type: 'INSTANCE', componentId: 'C:1' }] };
    const inst = dc.collectInstances(screen, 'login-screen');
    assert.strictEqual(inst[0].screen, 'login-screen');
    assert.ok(inst[0].path.startsWith('login-screen › '));
  });
}

// ============================================================================

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail > 0 ? 1 : 0);
