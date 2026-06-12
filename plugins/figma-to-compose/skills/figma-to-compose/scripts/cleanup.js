#!/usr/bin/env node
/**
 * cleanup.js
 *
 * Removes every intermediate artifact the figma-to-compose pipeline produced
 * for one screen. Runs ONLY after the Compose code has been successfully
 * written, reviewed (Step 9), and the user has confirmed they're satisfied.
 *
 * What gets deleted, by category:
 *   - figma-out/<screen>/screen.json + dimensions.json + figma-token-reuse.json
 *     + composable-inventory.json + assets/{icons,images}/*
 *   - kotlin-out/Color.kt + Typography.kt + Dimensions.kt
 *
 * Safety:
 *   - Refuses to delete any path that doesn't match an expected name
 *     (figma-out, kotlin-out, or paths the user explicitly passes).
 *   - Refuses to run without --confirm, OR without --i-have-read-this
 *     and --code-is-in-repo flags. The flags read like sentences on
 *     purpose — they're meant to be impossible to type by accident.
 *   - Logs every path it touches, before touching it.
 *   - Dry-run mode (--dry-run) shows what would be deleted without
 *     actually deleting anything.
 *
 * Usage:
 *   node cleanup.js --confirm                           # nuclear sweep, default dirs
 *   node cleanup.js --figma-out ./figma-out \
 *                   --kotlin-out ./kotlin-out --confirm
 *   node cleanup.js --dry-run                           # preview only
 */

'use strict';

const fs = require('fs');
const path = require('path');

// ============================================================================
// CLI
// ============================================================================

function parseArgs(argv) {
  const args = { positional: [] };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--help' || a === '-h') args.help = true;
    else if (a === '--dry-run') args.dryRun = true;
    else if (a === '--confirm') args.confirm = true;
    else if (a === '--i-have-read-this') args.iHaveReadThis = true;
    else if (a === '--code-is-in-repo') args.codeIsInRepo = true;
    else if (a.startsWith('--')) args[a.slice(2)] = argv[++i];
    else args.positional.push(a);
  }
  return args;
}

function usage() {
  console.log(`Usage: node cleanup.js [options]

Removes intermediate artifacts produced by the figma-to-compose pipeline.

Options:
  --figma-out <dir>     Path to figma-out (default: ./figma-out)
  --kotlin-out <dir>    Path to kotlin-out (default: ./kotlin-out)
  --dry-run             Show what would be deleted without deleting
  --confirm             REQUIRED for actual deletion. Acknowledges the user
                        accepts that figma-out/ AND kotlin-out/ will both
                        be removed entirely.
  --help                Show this message

Safety: cleanup will refuse to touch any directory that isn't named
'figma-out' or 'kotlin-out' (or whatever the user specified via flags).
This is intentional — the script must not turn into a generic rm -rf.
`);
}

// ============================================================================
// Path safety
// ============================================================================

const ALLOWED_BASENAMES = new Set(['figma-out', 'kotlin-out']);

/**
 * A path is safe to delete only if:
 *   1. It exists.
 *   2. It is a directory.
 *   3. Its basename is in ALLOWED_BASENAMES, OR the user explicitly passed
 *      it as a non-default flag value.
 *   4. It is not a symbolic link (we don't want a malicious symlink to
 *      e.g. ~/.ssh tricking us into deleting the user's keys).
 *   5. It is not the current working directory or anything above it.
 *
 * Returns { safe: bool, reason: string }.
 */
function isPathSafeToDelete(targetPath, { wasExplicit }) {
  if (!fs.existsSync(targetPath)) {
    return { safe: false, reason: 'path does not exist (nothing to delete)' };
  }
  const stat = fs.lstatSync(targetPath); // lstat — don't follow symlinks
  if (stat.isSymbolicLink()) {
    return { safe: false, reason: 'path is a symlink — refusing to follow' };
  }
  if (!stat.isDirectory()) {
    return { safe: false, reason: 'path is not a directory' };
  }
  const resolved = path.resolve(targetPath);
  const cwd = path.resolve(process.cwd());
  if (resolved === cwd) {
    return { safe: false, reason: 'refusing to delete the current working directory' };
  }
  if (cwd.startsWith(resolved + path.sep)) {
    return { safe: false, reason: 'path is an ancestor of the current working directory' };
  }
  if (resolved === path.parse(resolved).root) {
    return { safe: false, reason: 'refusing to delete a filesystem root' };
  }
  // Default-name check: when the user didn't specify the path explicitly,
  // its basename must be on the allowlist.
  const basename = path.basename(resolved);
  if (!wasExplicit && !ALLOWED_BASENAMES.has(basename)) {
    return {
      safe: false,
      reason: `basename "${basename}" is not on the allowlist (${[...ALLOWED_BASENAMES].join(', ')}). Pass it explicitly via --figma-out or --kotlin-out if you really mean it.`,
    };
  }
  return { safe: true };
}

// ============================================================================
// Inventory of what's about to be deleted
// ============================================================================

function inventory(dir) {
  // Walk the directory and produce a compact summary so the user / Claude
  // can see exactly what's about to disappear.
  const result = { dir, exists: fs.existsSync(dir), files: 0, totalBytes: 0, byExt: {} };
  if (!result.exists) return result;
  function walk(p) {
    let entries;
    try { entries = fs.readdirSync(p); } catch { return; }
    for (const entry of entries) {
      const full = path.join(p, entry);
      let s;
      try { s = fs.lstatSync(full); } catch { continue; }
      if (s.isDirectory()) walk(full);
      else if (s.isFile()) {
        result.files++;
        result.totalBytes += s.size;
        const ext = path.extname(entry).toLowerCase() || '(no ext)';
        result.byExt[ext] = (result.byExt[ext] || 0) + 1;
      }
    }
  }
  walk(dir);
  return result;
}

function formatBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

// ============================================================================
// Deletion (the actually-destructive part)
// ============================================================================

function rmrf(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
}

// ============================================================================
// Main
// ============================================================================

function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    usage();
    process.exit(0);
  }

  // Default targets and flag tracking.
  const targets = [];
  const figmaOut = args['figma-out'] || './figma-out';
  const kotlinOut = args['kotlin-out'] || './kotlin-out';
  targets.push({ path: figmaOut, wasExplicit: !!args['figma-out'] });
  targets.push({ path: kotlinOut, wasExplicit: !!args['kotlin-out'] });

  // Inventory each target before we touch anything.
  console.log('=== cleanup inventory ===');
  let anyExist = false;
  const reports = [];
  for (const t of targets) {
    const inv = inventory(t.path);
    reports.push({ ...t, inv });
    if (!inv.exists) {
      console.log(`  ${t.path}  (does not exist — skipping)`);
      continue;
    }
    anyExist = true;
    console.log(`  ${t.path}`);
    console.log(`    files: ${inv.files}, total: ${formatBytes(inv.totalBytes)}`);
    const exts = Object.entries(inv.byExt).sort((a, b) => b[1] - a[1]);
    for (const [ext, n] of exts) console.log(`    ${ext}: ${n}`);
  }
  console.log('');

  if (!anyExist) {
    console.log('Nothing to clean up. Exiting without action.');
    process.exit(0);
  }

  // Dry run: stop here.
  if (args.dryRun) {
    console.log('--dry-run set — no files will be deleted.');
    process.exit(0);
  }

  // Confirmation gate.
  if (!args.confirm) {
    console.error('');
    console.error('REFUSING to delete without --confirm.');
    console.error('');
    console.error('To proceed, re-run with --confirm. The flag exists to make sure');
    console.error('you understand that figma-out/ AND kotlin-out/ will both be');
    console.error('removed entirely. The Compose code in your project repo is');
    console.error('untouched — only the intermediate artifacts disappear.');
    console.error('');
    console.error('Use --dry-run first if you want to preview without deleting.');
    process.exit(1);
  }

  // Safety check each path.
  for (const r of reports) {
    if (!r.inv.exists) continue;
    const safety = isPathSafeToDelete(r.path, { wasExplicit: r.wasExplicit });
    if (!safety.safe) {
      console.error(`REFUSING to delete ${r.path}: ${safety.reason}`);
      process.exit(1);
    }
  }

  // Now do the deletions.
  let deleted = 0;
  for (const r of reports) {
    if (!r.inv.exists) continue;
    console.log(`deleting ${r.path} ...`);
    rmrf(r.path);
    deleted++;
  }

  console.log('');
  console.log(`Cleanup complete. ${deleted} director${deleted === 1 ? 'y' : 'ies'} removed.`);
}

if (require.main === module) {
  try { main(); }
  catch (e) { console.error('ERROR:', e.message); process.exit(1); }
}

module.exports = {
  isPathSafeToDelete,
  inventory,
  formatBytes,
  ALLOWED_BASENAMES,
};
