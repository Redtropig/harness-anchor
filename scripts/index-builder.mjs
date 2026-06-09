#!/usr/bin/env node
/**
 * index-builder.mjs — Generate PROJECT-TOC.md for a target project.
 *
 * Algorithm:
 *   1. Walk git ls-files in --target dir
 *   2. Skip binaries, large files, build dirs, the TOC itself
 *   3. For each remaining file, extract a one-line summary (first non-empty
 *      comment/docstring/text line, ≤80 chars)
 *   4. Preserve the existing `## Decisions` section
 *   5. Write header with `<!-- generated-at-commit: <HEAD SHA> -->`
 *
 * Usage:
 *   node index-builder.mjs --target /path/to/project [--output PROJECT-TOC.md]
 *
 * Security note: uses execFileSync (no shell) to avoid injection — see PR-review
 * guidance, even though our argv is hardcoded git commands.
 */

import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, statSync, existsSync, mkdirSync, unlinkSync } from 'node:fs';
import { resolve, join, basename } from 'node:path';
import { argv, exit } from 'node:process';

// ---- args ----
const args = {};
for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--target') args.target = argv[++i];
    else if (a === '--output') args.output = argv[++i];
    else if (a === '--help' || a === '-h') {
        console.log('Usage: node index-builder.mjs --target <dir> [--output PROJECT-TOC.md]');
        exit(0);
    }
}
const TARGET = resolve(args.target || process.cwd());
const OUTPUT = join(TARGET, args.output || 'PROJECT-TOC.md');

// ---- helpers ----
/** Run git with arg array — no shell, no injection surface. */
function git(...gitArgs) {
    return execFileSync('git', gitArgs, { cwd: TARGET, encoding: 'utf8' }).trim();
}

function inGitRepo() {
    try { git('rev-parse', '--git-dir'); return true; }
    catch { return false; }
}

const SKIP_DIRS = ['node_modules/', '.harness-anchor/', 'build/', '.build/', 'dist/', 'out/', '.next/', 'target/'];
const SKIP_FILES = ['PROJECT-TOC.md', 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'Cargo.lock'];
const MAX_BYTES = 100 * 1024;

function shouldSkip(relPath) {
    if (SKIP_FILES.includes(basename(relPath))) return true;
    return SKIP_DIRS.some(d => relPath.startsWith(d) || relPath.includes('/' + d));
}

function isProbablyBinary(buf) {
    const len = Math.min(buf.length, 1024);
    for (let i = 0; i < len; i++) {
        if (buf[i] === 0) return true;  // NUL byte → binary
    }
    return false;
}

/**
 * Extract a one-line summary from file content.
 * Strategy:
 *   1. Skip leading blank lines + shebang
 *   2. First comment line (// ... or # ... or /* ... or """...""" or <!-- ... -->)
 *   3. Else first non-empty line
 * Truncate to 80 chars.
 */
function extractSummary(content, relPath) {
    const lines = content.split('\n');
    let i = 0;
    while (i < lines.length && (lines[i].trim() === '' || lines[i].startsWith('#!'))) i++;

    for (; i < lines.length; i++) {
        const line = lines[i].trim();
        if (line === '') continue;

        // Strip common comment markers
        let summary = line
            .replace(/^\/\/\s*/, '')
            .replace(/^\/\*+\s*/, '')
            .replace(/\s*\*+\/$/, '')
            .replace(/^\*\s*/, '')
            .replace(/^#\s*/, '')
            .replace(/^;;\s*/, '')
            .replace(/^--\s*/, '')
            .replace(/^"""\s*/, '')
            .replace(/^<!--\s*/, '')
            .replace(/\s*--!?>$/, '') // strips --> and --!> (both HTML comment-end forms)
            .trim();

        if (summary.length === 0) continue;
        if (summary.length > 80) summary = summary.slice(0, 77) + '...';
        return summary;
    }
    return `(${basename(relPath)})`;
}

function readDecisionsSection(existingPath) {
    if (!existsSync(existingPath)) return '';
    const old = readFileSync(existingPath, 'utf8');
    const m = old.match(/^## Decisions\b[\s\S]*$/m);
    return m ? m[0] : '';
}

/**
 * Build the `## Directory map` body from the (already path-sorted) entries.
 * One line per directory — every ancestor, not just leaf dirs — with its direct-file
 * count and direct-subdir count. Deterministic (no LLM): the "forest" view that lets
 * the SessionStart hook inject just the shallow/top-level dirs for any repo size.
 */
function buildDirectoryMap(entries) {
    const directFiles = new Map();   // dir -> # files directly in it
    const childDirs = new Map();     // dir -> Set of direct child dir segments
    const allDirs = new Set();

    const ensure = (dir) => {
        if (!directFiles.has(dir)) directFiles.set(dir, 0);
        if (!childDirs.has(dir)) childDirs.set(dir, new Set());
        allDirs.add(dir);
    };
    ensure('.');

    for (const { rel } of entries) {
        const parts = rel.split('/');
        const dirParts = parts.slice(0, -1); // drop the filename
        let parent = '.';
        for (let k = 0; k < dirParts.length; k++) {
            const dir = dirParts.slice(0, k + 1).join('/');
            ensure(dir);
            childDirs.get(parent).add(dirParts[k]);
            parent = dir;
        }
        const immediate = dirParts.length === 0 ? '.' : dirParts.join('/');
        directFiles.set(immediate, (directFiles.get(immediate) || 0) + 1);
    }

    const dirs = [...allDirs].sort((a, b) => a.localeCompare(b));
    return dirs.map(d => {
        const f = directFiles.get(d) || 0;
        const sub = (childDirs.get(d) || new Set()).size;
        const label = d === '.' ? '`.` (root)' : `\`${d}/\``;
        const bits = [`${f} file${f === 1 ? '' : 's'}`];
        if (sub > 0) bits.push(`${sub} subdir${sub === 1 ? '' : 's'}`);
        return `- ${label} — ${bits.join(', ')}`;
    }).join('\n');
}

// ---- error log helper (Layer D) ----
const ERROR_LOG_DIR = join(TARGET, '.harness-anchor');
const ERROR_LOG_PATH = join(ERROR_LOG_DIR, 'last-error.log');

function writeErrorLog(message) {
    try {
        mkdirSync(ERROR_LOG_DIR, { recursive: true });
        writeFileSync(ERROR_LOG_PATH, `[${new Date().toISOString()}] ${message}\n`);
    } catch { /* best effort — never let logging failure mask the real error */ }
}

function clearErrorLog() {
    try { unlinkSync(ERROR_LOG_PATH); } catch { /* not present = fine */ }
}

// ---- main ----
try {
    if (!inGitRepo()) {
        throw new Error(`target is not a git repository: ${TARGET}`);
    }

    const head = git('rev-parse', 'HEAD').slice(0, 12);
    const files = git('ls-files').split('\n').filter(Boolean);

    const entries = [];
    let skipped = 0;
    for (const rel of files) {
        if (shouldSkip(rel)) { skipped++; continue; }
        const abs = join(TARGET, rel);
        try {
            const st = statSync(abs);
            if (!st.isFile()) continue;
            if (st.size > MAX_BYTES) { skipped++; continue; }
            const buf = readFileSync(abs);
            if (isProbablyBinary(buf)) { skipped++; continue; }
            const content = buf.toString('utf8');
            const summary = extractSummary(content, rel);
            entries.push({ rel, summary });
        } catch {
            skipped++;
        }
    }

    entries.sort((a, b) => a.rel.localeCompare(b.rel));

    const decisionsSection = readDecisionsSection(OUTPUT) ||
        '## Decisions\n\n<!-- Long-lived design decisions; one line each.\n- 2026-05-15: example decision (see docs/decisions/0001.md)\n-->\n';

    const dirMap = buildDirectoryMap(entries);

    const header = `<!-- generated-at-commit: ${head} -->
<!-- DO NOT EDIT BY HAND — run /index-project or scripts/index-builder.mjs -->

# PROJECT TOC

> One-line index of every git-tracked source file. ${entries.length} entries (${skipped} skipped).
> Navigate the **Directory map** (forest) first, then drill into **Files** (leaves).

## Directory map

${dirMap}

## Files

${entries.map(e => `- \`${e.rel}\` — ${e.summary}`).join('\n')}

${decisionsSection}`;

    writeFileSync(OUTPUT, header);
    console.log(`PROJECT-TOC.md regenerated: ${entries.length} files indexed, ${skipped} skipped. Anchor commit: ${head}`);
    clearErrorLog();  // success → remove stale error log
} catch (err) {
    console.error('FATAL:', err.message);
    writeErrorLog(`index-builder.mjs fatal: ${err.message}\nStack: ${err.stack}`);
    exit(2);
}
