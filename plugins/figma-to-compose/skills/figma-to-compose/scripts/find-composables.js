#!/usr/bin/env node
/**
 * find-composables.js
 *
 * Walks the user's Kotlin codebase and produces a catalogue of every
 * @Composable function that already exists, so the code-gen step can
 * REUSE or EXTEND them rather than synthesizing parallel implementations.
 *
 * The output is consumed by Claude during code generation: before writing
 * any new composable, look for an existing one in the inventory whose
 * category and signature suggest it could be reused or extended.
 *
 * What this script does NOT do: decide for Claude whether a match is a
 * good fit. That is a judgment call that requires reading the actual code,
 * understanding the design intent, and proposing extensions to the user
 * when modification is warranted. The inventory is the *catalogue*, not
 * the *decision*.
 *
 * Usage:
 *   node find-composables.js <repo-path> [options]
 *
 * Options:
 *   --out <dir>       Output directory (default: same dir as repo path)
 *   --max-body <n>    Lines of body to capture per composable (default: 30)
 *   --json-out        Print to stdout instead of writing a file
 *   --help            Show this message
 *
 * Output:
 *   composable-inventory.json — { composables: [{name, file, category,
 *     signature, parameters, body}], scanned: { files, count } }
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
    else if (a === '--json-out') args.jsonOut = true;
    else if (a.startsWith('--')) args[a.slice(2)] = argv[++i];
    else args.positional.push(a);
  }
  return args;
}

function usage() {
  console.log(`Usage: node find-composables.js <repo-path> [options]

Options:
  --out <dir>       Output directory (default: same dir as repo path)
  --max-body <n>    Lines of body to capture per composable (default: 30)
  --json-out        Print to stdout instead of writing a file
  --help            Show this message
`);
}

// ============================================================================
// File discovery
// ============================================================================

const SKIP_DIRS = new Set([
  'build', '.gradle', 'generated', 'node_modules',
  '.git', '.idea', '.kotlin', 'kotlin-js-store',
]);

// Test sources and previews are intentionally excluded — these would clutter
// the inventory with composables that aren't real reusable components.
const SKIP_PATH_PARTS = ['/test/', '/androidTest/', '/iosTest/', '/commonTest/'];

function isInterestingFile(filepath) {
  if (!filepath.endsWith('.kt')) return false;
  for (const part of SKIP_PATH_PARTS) {
    if (filepath.includes(part)) return false;
  }
  return true;
}

function walkKotlin(dir, files = []) {
  let entries;
  try { entries = fs.readdirSync(dir); }
  catch { return files; }

  for (const entry of entries) {
    if (entry.startsWith('.')) continue;
    if (SKIP_DIRS.has(entry)) continue;
    const full = path.join(dir, entry);
    let stat;
    try { stat = fs.statSync(full); }
    catch { continue; }
    if (stat.isDirectory()) walkKotlin(full, files);
    else if (isInterestingFile(full)) files.push(full);
  }
  return files;
}

// ============================================================================
// Composable extraction
//
// We deliberately use a regex-based extraction rather than a full Kotlin
// parser. The skill needs ENOUGH information to find candidates and present
// them to Claude — full AST analysis would be overkill, brittle, and
// slow. Edge cases (nested generics in parameters, multi-line annotations,
// trailing lambdas in signatures) are tolerated as best-effort; if a
// composable doesn't parse cleanly the inventory drops it rather than
// emitting half-broken metadata.
// ============================================================================

const PREVIEW_RE = /@Preview\b/;
const PRIVATE_RE = /\bprivate\s+(?:internal\s+)?fun\b/;

/**
 * Find @Composable functions in a Kotlin source file. Returns an array of
 * { name, signature, paramText, paramList, bodyExcerpt, isPreview, isPrivate }.
 *
 * Skips: @Preview composables (they're the SAME composable invoked for
 * tooling, not a separate component) and private composables (they can't
 * be reused outside their file).
 */
function extractComposables(source, opts = {}) {
  const maxBody = opts.maxBody || 30;
  const composables = [];

  // Match @Composable annotation followed by an optional visibility
  // modifier and a fun declaration. We deliberately accept any number of
  // lines / annotations between @Composable and `fun` because Compose code
  // routinely chains @Composable + @Stable + @ExperimentalFoundationApi etc.
  //
  // Capture group 1 is the modifier+annotation block between @Composable
  // and `fun`. Capture group 2 is the function name.
  const composableHeaderRe =
    /@Composable\s*([^{]*?)\bfun\s+([A-Z][A-Za-z0-9_]*)\s*(?:<[^>]+>\s*)?\(/g;

  let m;
  while ((m = composableHeaderRe.exec(source)) !== null) {
    const annotationsAndModifiers = m[1];
    const name = m[2];
    const headerEnd = m.index + m[0].length;

    // The captured header ended at the OPEN paren of the parameter list.
    // Walk forward, balancing parens to find the close paren.
    const paramText = extractBalanced(source, headerEnd - 1, '(', ')');
    if (!paramText) continue;
    const paramListEnd = headerEnd - 1 + paramText.length;

    // After the parameter list, we may have `: ReturnType` and then `{` or `=`.
    // Find the body. If there's no body block (expression body), capture
    // the expression instead — many composables are one-liner delegates.
    const afterParams = source.slice(paramListEnd);
    const blockMatch = afterParams.match(/^\s*(?::\s*[^={]+)?\s*([={])/);
    if (!blockMatch) continue;

    const bodyStartOffset = paramListEnd + blockMatch.index + blockMatch[0].length - 1;
    let bodyExcerpt = '';
    if (blockMatch[1] === '{') {
      const bodyText = extractBalanced(source, bodyStartOffset, '{', '}');
      if (bodyText) {
        // Strip outer braces, take first N lines for the excerpt.
        const inner = bodyText.slice(1, -1);
        bodyExcerpt = inner.split('\n').slice(0, maxBody).join('\n').trim();
      }
    } else {
      // Expression-bodied composable. Capture up to next top-level newline.
      const expr = afterParams.slice(blockMatch.index + 1);
      bodyExcerpt = expr.split('\n').slice(0, maxBody).join('\n').trim();
    }

    // Reconstruct the signature line as the user would read it.
    const headerStart = source.lastIndexOf('@Composable', m.index + 1);
    const signatureSlice = source.slice(headerStart, paramListEnd + 1);
    const signature = signatureSlice.replace(/\s+/g, ' ').trim();

    const params = parseParams(paramText.slice(1, -1));

    composables.push({
      name,
      signature,
      paramText,
      paramList: params,
      bodyExcerpt,
      isPreview: PREVIEW_RE.test(annotationsAndModifiers) ||
                 PREVIEW_RE.test(source.slice(Math.max(0, headerStart - 200), headerStart)),
      isPrivate: PRIVATE_RE.test(annotationsAndModifiers) ||
                 /\bprivate\b/.test(annotationsAndModifiers),
    });
  }

  return composables;
}

/**
 * Walk a string from `start` (which should be on the open delimiter) and
 * return the substring up to and including the matching close delimiter.
 * Handles nested same-type pairs. Returns null if no balance is found.
 *
 * Naive about strings/comments — won't correctly skip a `}` inside a string
 * literal or `//` comment. In practice this catches >99% of well-formed
 * Kotlin we care about; pathological code will just produce a slightly
 * truncated entry, never a crash.
 */
function extractBalanced(s, start, openCh, closeCh) {
  if (s[start] !== openCh) return null;
  let depth = 0;
  for (let i = start; i < s.length; i++) {
    const c = s[i];
    if (c === openCh) depth++;
    else if (c === closeCh) {
      depth--;
      if (depth === 0) return s.slice(start, i + 1);
    }
  }
  return null;
}

/**
 * Split a parameter list into individual parameter entries. Tolerates
 * generics, default values containing commas, and trailing commas.
 *
 * Returns: [{ name, type, hasDefault, defaultExpr? }, ...]
 */
function parseParams(paramText) {
  if (!paramText.trim()) return [];
  const params = [];
  // Split on top-level commas, where "top-level" means not inside any of:
  //  - angle brackets <>  (generics like List<Int>)
  //  - parens ()          (lambda/function types like (Int) -> Unit)
  //  - braces {}          (default-value blocks)
  //  - square brackets [] (array literals, rare in params)
  //  - string literals    (default values can be "abc, def")
  // Each family has its own depth counter — they don't combine.
  const parts = [];
  let angle = 0, paren = 0, brace = 0, bracket = 0;
  let inString = false;
  let buffer = '';
  for (let i = 0; i < paramText.length; i++) {
    const c = paramText[i];
    if (c === '"' && paramText[i - 1] !== '\\') inString = !inString;
    if (!inString) {
      if (c === '<') angle++;
      else if (c === '>') {
        // Distinguish '>' as generic-close from '->'. A '>' preceded by '-'
        // is part of a lambda arrow and must not decrement angle depth.
        if (paramText[i - 1] !== '-' && angle > 0) angle--;
      }
      else if (c === '(') paren++;
      else if (c === ')') paren--;
      else if (c === '{') brace++;
      else if (c === '}') brace--;
      else if (c === '[') bracket++;
      else if (c === ']') bracket--;
      else if (c === ',' && angle === 0 && paren === 0 && brace === 0 && bracket === 0) {
        parts.push(buffer.trim());
        buffer = '';
        continue;
      }
    }
    buffer += c;
  }
  if (buffer.trim()) parts.push(buffer.trim());

  for (const part of parts) {
    // Find the FIRST '=' that's at top level — default values can contain
    // additional '=' signs (e.g., named args inside the default expression).
    let eqIdx = -1;
    let a = 0, p = 0, b = 0, br = 0, str = false;
    for (let i = 0; i < part.length; i++) {
      const c = part[i];
      if (c === '"' && part[i - 1] !== '\\') str = !str;
      if (!str) {
        if (c === '<') a++;
        else if (c === '>' && part[i - 1] !== '-' && a > 0) a--;
        else if (c === '(') p++;
        else if (c === ')') p--;
        else if (c === '{') b++;
        else if (c === '}') b--;
        else if (c === '[') br++;
        else if (c === ']') br--;
        else if (c === '=' && part[i + 1] !== '=' && part[i - 1] !== '!' &&
                 a === 0 && p === 0 && b === 0 && br === 0) {
          eqIdx = i;
          break;
        }
      }
    }
    let head, defaultExpr;
    if (eqIdx === -1) {
      head = part.trim();
    } else {
      head = part.slice(0, eqIdx).trim();
      defaultExpr = part.slice(eqIdx + 1).trim();
    }
    // head is "name: Type" — split on the FIRST top-level colon. The colon
    // inside `Map<String, Int>` doesn't count, but at top level, the first
    // colon separates name from type.
    let colonIdx = -1;
    let a2 = 0, p2 = 0;
    for (let i = 0; i < head.length; i++) {
      const c = head[i];
      if (c === '<') a2++;
      else if (c === '>' && head[i - 1] !== '-' && a2 > 0) a2--;
      else if (c === '(') p2++;
      else if (c === ')') p2--;
      else if (c === ':' && a2 === 0 && p2 === 0) { colonIdx = i; break; }
    }
    if (colonIdx === -1) continue;
    const name = head.slice(0, colonIdx).trim();
    const type = head.slice(colonIdx + 1).trim();
    params.push({
      name, type,
      hasDefault: defaultExpr != null,
      ...(defaultExpr != null ? { defaultExpr } : {}),
    });
  }
  return params;
}

// ============================================================================
// Categorisation
//
// A coarse hint to make searching the inventory practical. Categories are
// inferred from the composable's name + body keywords. The point is to
// give Claude a good first-pass filter before reading bodies, not to
// produce a perfect taxonomy.
// ============================================================================

/**
 * Normalise a composable name into lowercase tokens so camelCase /
 * PascalCase boundaries become real word boundaries we can match.
 * "AppTopBar" → "app top bar"; "PrimaryFAB" → "primary fab".
 */
function normaliseNameForCategory(name) {
  return String(name)
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1 $2')
    .toLowerCase();
}

const CATEGORY_RULES = [
  { category: 'top-bar',     namePat: /\b(top ?bar|app ?bar|toolbar|header)\b/i,
    bodyPat: /\b(TopAppBar|CenterAlignedTopAppBar)\b/ },
  { category: 'bottom-bar',  namePat: /\b(bottom ?bar|tab ?bar|nav ?bar|navigation ?bar)\b/i,
    bodyPat: /\b(BottomAppBar|NavigationBar)\b/ },
  { category: 'bottom-sheet',namePat: /\b(bottom ?sheet|sheet|drawer)\b/i,
    bodyPat: /\b(ModalBottomSheet|BottomSheetScaffold|Drawer)\b/ },
  { category: 'dialog',      namePat: /\b(dialog|alert|popup|modal)\b/i,
    bodyPat: /\b(AlertDialog|Dialog)\b/ },
  { category: 'button',      namePat: /\b(button|fab|action)\b/i,
    bodyPat: /\b(Button|FloatingActionButton|IconButton|TextButton|OutlinedButton|FilledTonalButton)\b/ },
  { category: 'card',        namePat: /\b(card|tile|item)\b/i,
    bodyPat: /\b(Card|ElevatedCard|OutlinedCard)\b/ },
  { category: 'list-item',   namePat: /\b(list ?item|row|cell)\b/i,
    bodyPat: /\bListItem\b/ },
  { category: 'input',       namePat: /\b(input|field|text ?field|search)\b/i,
    bodyPat: /\b(TextField|OutlinedTextField|BasicTextField)\b/ },
  { category: 'chip',        namePat: /\b(chip|tag|badge|pill)\b/i,
    bodyPat: /\b(Chip|FilterChip|InputChip|AssistChip|SuggestionChip)\b/ },
  { category: 'avatar',      namePat: /\b(avatar|profile)\b/i,
    bodyPat: null },
  { category: 'icon',        namePat: /\b(icon|symbol|glyph)\b/i,
    bodyPat: /\bIcon\b/ },
  { category: 'screen',      namePat: /\b(screen|page|view)\b/i,
    bodyPat: /\bScaffold\b/ },
];

function categorise(name, bodyExcerpt) {
  const normalised = normaliseNameForCategory(name);
  for (const rule of CATEGORY_RULES) {
    const nameHit = rule.namePat && rule.namePat.test(normalised);
    const bodyHit = rule.bodyPat && rule.bodyPat.test(bodyExcerpt);
    if (nameHit || bodyHit) return rule.category;
  }
  return 'other';
}

// ============================================================================
// Main
// ============================================================================

function buildInventory(repoPath, opts = {}) {
  const files = walkKotlin(repoPath);
  const composables = [];
  const filesScanned = [];

  for (const file of files) {
    let source;
    try { source = fs.readFileSync(file, 'utf8'); }
    catch { continue; }

    // Skip files that have no @Composable at all — fast path.
    if (!source.includes('@Composable')) continue;

    const found = extractComposables(source, opts);
    if (!found.length) continue;

    let touched = false;
    for (const c of found) {
      // Skip @Preview functions and private composables — neither is
      // intended for cross-file reuse.
      if (c.isPreview) continue;
      if (c.isPrivate) continue;

      composables.push({
        name: c.name,
        file: path.relative(repoPath, file),
        category: categorise(c.name, c.bodyExcerpt),
        signature: c.signature,
        parameters: c.paramList.map(p => ({
          name: p.name, type: p.type, hasDefault: p.hasDefault,
        })),
        body: c.bodyExcerpt,
      });
      touched = true;
    }
    if (touched) filesScanned.push(path.relative(repoPath, file));
  }

  // Group by category for easier scanning.
  const byCategory = {};
  for (const c of composables) {
    if (!byCategory[c.category]) byCategory[c.category] = [];
    byCategory[c.category].push(c.name);
  }

  return {
    generatedAt: new Date().toISOString(),
    repoPath: path.resolve(repoPath),
    scanned: { files: filesScanned.length, composables: composables.length },
    byCategory,
    composables,
  };
}

function main() {
  const args = parseArgs(process.argv);
  if (args.help || !args.positional[0]) {
    usage();
    process.exit(args.help ? 0 : 1);
  }
  const repoPath = args.positional[0];
  if (!fs.existsSync(repoPath)) {
    console.error(`Path does not exist: ${repoPath}`);
    process.exit(1);
  }

  const inventory = buildInventory(repoPath, {
    maxBody: Number(args['max-body']) || 30,
  });

  if (args.jsonOut) {
    console.log(JSON.stringify(inventory, null, 2));
    return;
  }

  const outDir = args.out || repoPath;
  fs.mkdirSync(outDir, { recursive: true });
  const outFile = path.join(outDir, 'composable-inventory.json');
  fs.writeFileSync(outFile, JSON.stringify(inventory, null, 2));

  console.log(`Scanned ${inventory.scanned.files} files, found ${inventory.scanned.composables} reusable composable(s).`);
  console.log(`  -> ${path.resolve(outFile)}`);
  if (inventory.scanned.composables) {
    console.log('');
    console.log('By category:');
    for (const [cat, names] of Object.entries(inventory.byCategory)) {
      console.log(`  ${cat}: ${names.slice(0, 5).join(', ')}${names.length > 5 ? `, +${names.length - 5} more` : ''}`);
    }
  }
}

if (require.main === module) {
  try { main(); }
  catch (e) { console.error('ERROR:', e.message); process.exit(1); }
}

module.exports = {
  walkKotlin,
  extractComposables,
  parseParams,
  extractBalanced,
  categorise,
  buildInventory,
};
