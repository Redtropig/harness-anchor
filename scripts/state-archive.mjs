#!/usr/bin/env node
/**
 * state-archive.mjs — Move cold history out of the hot state files, verbatim.
 *
 * Hot-window contract (fixed defaults; documented in feature-state-keeper /
 * context-budget-discipline):
 *   progress.md        keeps the newest PROGRESS_KEEP sections (prepend contract puts
 *                      newest first); older sections move to progress-archive.md,
 *                      prepended so the archive stays newest-archived-first.
 *   feature_list.json  keeps every non-pass feature + the PASS_KEEP most recently
 *                      completed pass entries; older pass entries move — evidence
 *                      objects intact — to feature_archive.json (same schema shape,
 *                      no extra per-entry fields; git history records when).
 *
 * Safety contract:
 *   - Deterministic + idempotent: a second run is a no-op (exit 0, zero diff).
 *   - Archive-first write order: a crash between writes leaves duplicates, never
 *     loss; the duplicate guard makes the re-run converge (identical content already
 *     archived → skipped on write, still removed from hot). Same key with DIFFERENT
 *     content → abort, no writes (never silently merge).
 *   - Malformed JSON / unexpected shape / a ledger with duplicate feature ids →
 *     exit 1, no writes. This tool never "repairs" the ledger — and never operates
 *     on a corrupt one (feature-list-validate.mjs is the fix path).
 *   - Moves, never deletes: archives are ordinary git-tracked files (grep-friendly).
 *   - Hot progress.md rewrite normalizes inter-section spacing to one blank line.
 *
 * Usage: node state-archive.mjs [--dry-run] [--target <dir>]   (target = cwd default)
 * Exit:  0 = archived or nothing to do; 1 = hard error (nothing written).
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { argv, exit } from 'node:process';

const PROGRESS_KEEP = 20;
const PASS_KEEP = 10;

let dryRun = false;
let target = process.cwd();
for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--dry-run') {
        dryRun = true;
    } else if (argv[i] === '--target') {
        // This tool WRITES into join(target, ...). A missing/empty value (e.g. an unset
        // shell variable) must not silently fall back to the cwd, and a flag must not be
        // eaten as a path — either way it would relocate the wrong project's state.
        const next = argv[i + 1];
        if (next === undefined || next === '' || next.startsWith('-')) {
            const got = (next === undefined || next === '') ? 'nothing' : `'${next}'`;
            console.error(`state-archive: --target requires a directory argument (got ${got}); refusing to fall back to the current directory. For a directory whose name starts with '-', pass it as ./<name>.`);
            exit(1);
        }
        target = next;
        i++;
    } else {
        console.error(`state-archive: unknown argument '${argv[i]}'`);
        exit(1);
    }
}
target = resolve(target);

const report = [];
const writes = [];   // [path, content] — flushed only if no hard error and not dry-run
let hardError = false;

// ---------- progress.md ----------

/** Header = through the FIRST `---` line (progress-prepend.mjs's rule); sections at `^## `. */
function splitProgress(text) {
    const lines = text.split('\n');
    const sep = lines.findIndex(l => l.trim() === '---');
    const headerEnd = sep === -1 ? 0 : sep + 1;
    const header = lines.slice(0, headerEnd);
    const sections = [];
    const preamble = [];
    let current = null;
    for (const line of lines.slice(headerEnd)) {
        if (line.startsWith('## ')) {
            if (current) sections.push(current);
            current = [line];
        } else if (current) {
            current.push(line);
        } else {
            preamble.push(line);
        }
    }
    if (current) sections.push(current);
    return { header, preamble, sections };
}

const sectionText = (sec) => sec.join('\n').replace(/\n+$/, '');

function archiveProgress() {
    const hotPath = join(target, 'progress.md');
    const archPath = join(target, 'progress-archive.md');
    if (!existsSync(hotPath)) { report.push('progress.md: absent — skipped'); return; }

    const { header, preamble, sections } = splitProgress(readFileSync(hotPath, 'utf8'));
    if (sections.length <= PROGRESS_KEEP) {
        report.push(`progress.md: ${sections.length} section(s) within hot window (${PROGRESS_KEEP})`);
        return;
    }
    const keep = sections.slice(0, PROGRESS_KEEP);   // newest-first per prepend contract
    const move = sections.slice(PROGRESS_KEEP);

    let archText = existsSync(archPath) ? readFileSync(archPath, 'utf8')
        : `# Progress Log — Archive

> Older sessions moved out of progress.md by state-archive.mjs (newest archived first).
> The hot window lives in progress.md; grep this file for history — do not load it whole.

---
`;

    // Duplicate guard, keyed on the section's `## ` header line.
    const archLines = new Set(archText.split('\n'));
    const toAdd = [];
    for (const sec of move) {
        if (archLines.has(sec[0])) {
            if (archText.includes(sectionText(sec))) continue;   // crash residue → already there
            console.error(`state-archive: conflict — '${sec[0]}' exists in progress-archive.md with different content; aborting (no writes)`);
            hardError = true;
            return;
        }
        toAdd.push(sec);
    }

    if (toAdd.length > 0) {
        const movedBlock = toAdd.map(sectionText).join('\n\n');
        const aLines = archText.split('\n');
        const aSep = aLines.findIndex(l => l.trim() === '---');
        let newArch;
        if (aSep === -1) {
            newArch = `${movedBlock}\n\n${archText.replace(/^\n+/, '')}`;
        } else {
            const aHead = aLines.slice(0, aSep + 1).join('\n');
            const aRest = aLines.slice(aSep + 1).join('\n').replace(/^\n+/, '');
            newArch = `${aHead}\n\n${movedBlock}\n\n${aRest}`;
        }
        writes.push([archPath, newArch.replace(/\n*$/, '\n')]);
    }

    // Hot rewrite: header (+ idempotent pointer line, for pre-v0.9.0 files) + kept sections.
    const headerOut = [...header];
    if (!headerOut.some(l => l.includes('progress-archive.md'))) {
        const at = headerOut.length > 0 && headerOut[headerOut.length - 1].trim() === '---'
            ? headerOut.length - 1 : headerOut.length;
        headerOut.splice(at, 0, '> Older sessions: progress-archive.md (moved by state-archive.mjs; history is never deleted).');
    }
    const pre = preamble.join('\n').replace(/^\n+|\n+$/g, '');
    const parts = [headerOut.join('\n')];
    if (pre) parts.push(pre);
    parts.push(keep.map(sectionText).join('\n\n'));
    writes.push([hotPath, parts.join('\n\n').replace(/\n*$/, '\n')]);

    report.push(`progress.md: ${sections.length} sections → keep ${PROGRESS_KEEP}, archive ${move.length} (${toAdd.length} new, ${move.length - toAdd.length} already archived)`);
}

// ---------- feature_list.json ----------

const completionKey = (f) =>
    f.completedAt || (f.evidence && f.evidence.timestamp) || f.createdAt || '';

/** Newest completion first; all-dates-missing sorts oldest; deterministic id tie-break. */
function byNewestFirst(a, b) {
    const ka = completionKey(a), kb = completionKey(b);
    if (ka !== kb) return ka < kb ? 1 : -1;
    const ia = a.id || '', ib = b.id || '';
    return ia < ib ? -1 : ia > ib ? 1 : 0;
}

function loadJson(path, label) {
    let data;
    try {
        data = JSON.parse(readFileSync(path, 'utf8'));
    } catch (err) {
        console.error(`state-archive: invalid JSON in ${label}: ${err && err.message ? err.message : err}; aborting (no writes)`);
        hardError = true;
        return null;
    }
    if (!data || !Array.isArray(data.features)) {
        console.error(`state-archive: unexpected shape in ${label} (no features array); aborting (no writes)`);
        hardError = true;
        return null;
    }
    return data;
}

function archiveFeatures() {
    const hotPath = join(target, 'feature_list.json');
    const archPath = join(target, 'feature_archive.json');
    if (!existsSync(hotPath)) { report.push('feature_list.json: absent — skipped'); return; }

    const data = loadJson(hotPath, 'feature_list.json');
    if (hardError) return;

    const passes = data.features.filter(f => f && f.status === 'pass');
    if (passes.length <= PASS_KEEP) {
        report.push(`feature_list.json: ${passes.length} pass within hot window (${PASS_KEEP})`);
        return;
    }

    // Refuse to archive from an invalid ledger: a duplicate id would either land twice in
    // the archive or manufacture a hot∩archive collision (one copy moves, one stays).
    // "Never repairs" implies never operating on corrupt input — feature-list-validate.mjs
    // is the fix path (rename the newer entry), then re-run.
    const idCounts = new Map();
    for (const f of data.features) {
        if (f && typeof f.id === 'string') idCounts.set(f.id, (idCounts.get(f.id) || 0) + 1);
    }
    const hotDups = [...idCounts.entries()].filter(([, n]) => n > 1).map(([id]) => id);
    if (hotDups.length > 0) {
        console.error(`state-archive: duplicate feature id(s) in feature_list.json: ${hotDups.map(i => `'${i}'`).join(', ')} — resolve via feature-list-validate.mjs guidance first; aborting (no writes)`);
        hardError = true;
        return;
    }

    const moveSet = new Set([...passes].sort(byNewestFirst).slice(PASS_KEEP));

    let arch;
    if (existsSync(archPath)) {
        arch = loadJson(archPath, 'feature_archive.json');
        if (hardError) return;
    } else {
        arch = {
            $schema: './feature_list.schema.json',
            project: data.project || '',
            description: 'Archived pass features moved out of feature_list.json by state-archive.mjs; read-only history — do not edit by hand',
            features: [],
        };
    }

    const archById = new Map(arch.features
        .filter(f => f && typeof f.id === 'string')
        .map(f => [f.id, f]));
    let added = 0, residue = 0;
    for (const f of moveSet) {
        const prior = archById.get(f.id);
        if (prior !== undefined) {
            if (JSON.stringify(prior) === JSON.stringify(f)) { residue++; continue; }  // crash residue
            console.error(`state-archive: conflict — feature id '${f.id}' exists in feature_archive.json with different content; aborting (no writes)`);
            hardError = true;
            return;
        }
        arch.features.push(f);
        added++;
    }
    arch.features.sort(byNewestFirst);

    data.features = data.features.filter(f => !moveSet.has(f));

    writes.push([archPath, JSON.stringify(arch, null, 2) + '\n']);
    writes.push([hotPath, JSON.stringify(data, null, 2) + '\n']);
    report.push(`feature_list.json: ${passes.length} pass → keep ${PASS_KEEP}, archive ${moveSet.size} (${added} new, ${residue} already archived)`);
}

// ---------- main ----------

archiveProgress();
if (hardError) exit(1);
archiveFeatures();
if (hardError) exit(1);

for (const line of report) console.log(line);
if (writes.length === 0) {
    console.log('nothing to archive');
    exit(0);
}
if (dryRun) {
    console.log('(dry-run: no files written)');
    exit(0);
}
try {
    for (const [p, content] of writes) writeFileSync(p, content);   // archive queued before hot
} catch (err) {
    console.error(`state-archive: write failed: ${err && err.message ? err.message : err} — state may be mid-relocation (archive-first order); fix the cause and re-run: the duplicate guard makes re-runs converge`);
    exit(1);
}
console.log('archived.');
exit(0);
