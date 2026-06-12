#!/usr/bin/env node
'use strict';

// ============================================================================
// figma-outline.js — selection step for figma-to-compose.
//
// Fetches the shallow structure of a node, annotates each direct child with a
// ROLE (instance / one-off / component-set), batch-renders one thumbnail per
// candidate (capped, scale 1), and writes outline-manifest.json. The model uses
// this to pick the target component / item to isolate, instead of hand-hunting
// node ids. Re-export at the chosen id (via figma-to-json) does the isolation.
// ============================================================================

const fs = require('fs');
const path = require('path');
const { BASE, parseFigmaUrl, figmaFetch, exportImages } = require('./figma-client');

const THUMB_CAP = 20;   // images-API fan-out cap (rate-limit friendly)

// ----- pure core (unit-tested) ---------------------------------------------

/**
 * Annotate a container's DIRECT children with a role. Pure; operates on the
 * normalized node shape { id, name, type, box, componentId? }.
 *   instance       — INSTANCE with a componentId (carries usedCount across siblings)
 *   component-set  — a Figma COMPONENT_SET (variant group)
 *   one-off        — everything else
 */
function annotateCandidates(container) {
  const children = container.children || [];
  const instanceCounts = {};
  for (const c of children) {
    if (c.type === 'INSTANCE' && c.componentId) {
      instanceCounts[c.componentId] = (instanceCounts[c.componentId] || 0) + 1;
    }
  }
  return children.map(c => {
    const base = { id: c.id, name: c.name, type: c.type, box: c.box || null };
    if (c.type === 'COMPONENT_SET') return { ...base, role: 'component-set' };
    if (c.type === 'INSTANCE' && c.componentId) {
      return { ...base, role: 'instance', componentId: c.componentId, usedCount: instanceCounts[c.componentId] };
    }
    return { ...base, role: 'one-off' };
  });
}

// ----- network shell --------------------------------------------------------

function normalizeChild(n) {
  const bb = n.absoluteBoundingBox;
  return {
    id: n.id, name: n.name, type: n.type, componentId: n.componentId,
    box: bb ? { w: Math.round(bb.width), h: Math.round(bb.height) } : null,
  };
}

async function fetchContainer(fileKey, nodeId, token, depth) {
  const url = `${BASE}/files/${fileKey}/nodes?ids=${encodeURIComponent(nodeId)}&depth=${depth}`;
  const data = await figmaFetch(url, token);
  const doc = data.nodes && data.nodes[nodeId] && data.nodes[nodeId].document;
  if (!doc) throw new Error(`Node ${nodeId} not found (check the URL points at a node you can access)`);
  return doc;
}

async function download(url, file) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`thumbnail download ${res.status}`);
  fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
}

const safeName = (id) => id.replace(/[^A-Za-z0-9]/g, '-');

function parseArgs(argv) {
  const args = { thumbs: false, depth: 2, out: './figma-out/outline' };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--thumbs') args.thumbs = true;
    else if (a === '--depth') args.depth = Number(argv[++i]);
    else if (a === '--out') args.out = argv[++i];
    else if (!a.startsWith('--')) args.url = a;
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv);
  const token = process.env.FIGMA_TOKEN;
  if (!args.url) { console.error('Usage: figma-outline.js <figma-url> [--thumbs] [--depth N] [--out DIR]'); process.exit(1); }
  if (!token) { console.error('FIGMA_TOKEN not set — create one (file_content:read) and export it.'); process.exit(2); }

  const { fileKey, nodeIds } = parseFigmaUrl(args.url);
  if (!nodeIds.length) { console.error('URL has no node-id. Right-click the frame in Figma → Copy link to selection.'); process.exit(3); }

  const container = await fetchContainer(fileKey, nodeIds[0], token, args.depth);
  const candidates = annotateCandidates(
    { children: (container.children || []).map(normalizeChild) }
  );

  fs.mkdirSync(args.out, { recursive: true });
  if (args.thumbs && candidates.length) {
    const ids = candidates.slice(0, THUMB_CAP).map(c => c.id);
    const { urls, failed } = await exportImages(fileKey, ids, { format: 'png', scale: 1 }, token);
    for (const c of candidates) {
      const u = urls[c.id];
      if (u) { const f = `${safeName(c.id)}.png`; await download(u, path.join(args.out, f)); c.thumbnail = f; }
    }
    if (failed.length) console.error(`  (${failed.length} node(s) Figma could not render)`);
    if (candidates.length > THUMB_CAP) console.error(`  (capped thumbnails at ${THUMB_CAP}; ${candidates.length} candidates total)`);
  }

  const manifest = {
    fileKey, containerId: nodeIds[0], containerName: container.name,
    candidateCount: candidates.length, candidates,
  };
  const manifestPath = path.join(args.out, 'outline-manifest.json');
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
  console.log(manifestPath);
  for (const c of candidates) {
    console.log(`  ${c.role.padEnd(13)} ${c.name}  (${c.id}${c.usedCount ? `, used ${c.usedCount}×` : ''})${c.thumbnail ? '  → ' + c.thumbnail : ''}`);
  }
}

if (require.main === module) {
  main().catch(e => { console.error('ERROR:', e.message); process.exit(1); });
}

module.exports = { annotateCandidates, normalizeChild };
