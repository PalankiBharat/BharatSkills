'use strict';

// ============================================================================
// figma-client.js — shared Figma REST plumbing.
//
// Extracted from figma-to-json.js so figma-to-json (full export) and
// figma-outline (selection/structure) share ONE URL parser, ONE retry policy,
// and ONE set of endpoint helpers. No drift between two copies.
// ============================================================================

const BASE = 'https://api.figma.com/v1';
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

/**
 * Parse a Figma URL into { fileKey, nodeIds }.
 * Handles: /file/, /design/, /proto/, /board/; branches; embed URLs;
 * URL-encoded node-ids; comma-separated node-ids (ALL returned — a modal target
 * is often a sheet frame plus a backdrop scrim). Rejects community URLs.
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
  // dash-to-colon replacement when no `:` is already present. ALL ids are kept.
  const rawNodeId = u.searchParams.get('node-id');
  const nodeIds = rawNodeId
    ? rawNodeId.trim().split(',').map(s => {
        const t = s.trim();
        return t.includes(':') ? t : t.replace(/-/g, ':');
      }).filter(Boolean)
    : [];

  return { fileKey, nodeIds };
}

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

module.exports = { BASE, sleep, parseFigmaUrl, figmaFetch, getNodes, getFile, exportImages };
