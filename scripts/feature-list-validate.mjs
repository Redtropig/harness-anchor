#!/usr/bin/env node
/**
 * feature-list-validate.mjs — Enforce feature `id` uniqueness in feature_list.json.
 *
 * JSON Schema draft-07 cannot express per-field uniqueness (`uniqueItems` is whole-object
 * equality), so feature_list.schema.json is structurally blind to id collisions. This is the
 * imperative companion that closes that gap — `id` is the lookup/mutation key for status and
 * evidence (/verify flips "the" feature by id), so a duplicate corrupts the source of truth.
 *
 * Read-only — never writes the file.
 *
 * Modes:
 *   node feature-list-validate.mjs [path]
 *       Validate the whole file. Exit 0 (silent) if all ids unique;
 *       exit 3 + "Duplicate feature id(s): 'x' (×2)" on collision;
 *       exit 1 on missing file / invalid JSON. Ids in a sibling feature_archive.json
 *       are part of the namespace (hot∩archive collision ⇒ exit 3; corrupt archive ⇒ exit 1).
 *
 *   node feature-list-validate.mjs --check <candidate-id> [path]
 *       Pre-write candidate test. Exit 0 if the id is free;
 *       exit 3 + "id 'x' already exists; try 'x-2'" if taken (first free -N suggested;
 *       archived ids count as taken);
 *       missing file ⇒ free (exit 0, no features yet); invalid JSON ⇒ exit 1.
 *
 * path defaults to ./feature_list.json. Exit codes: 0 ok · 3 duplicate/taken · 1 hard error.
 */

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { argv, exit } from 'node:process';

// ---- arg parsing ----
let checkId = null;
let path;
if (argv[2] === '--check') {
    checkId = argv[3];
    if (!checkId) {
        console.error('feature-list-validate: --check requires a candidate id');
        exit(1);
    }
    path = argv[4] || 'feature_list.json';
} else {
    path = argv[2] || 'feature_list.json';
}

// ---- read (in --check mode a missing file just means "no features yet") ----
let raw = null;
try {
    raw = readFileSync(path, 'utf8');
} catch {
    if (checkId === null) {
        console.error(`feature-list-validate: cannot read ${path}`);
        exit(1);
    }
    // --check with no hot file: fall through — archived ids must still be honored.
}

let data = { features: [] };
if (raw !== null) {
    try {
        data = JSON.parse(raw);
    } catch (err) {
        console.error(`feature-list-validate: invalid JSON in ${path}: ${err && err.message ? err.message : err}`);
        exit(1);
    }
}

const features = (data && Array.isArray(data.features)) ? data.features : [];
const ids = features
    .map(f => (f && typeof f.id === 'string') ? f.id : null)
    .filter(id => id !== null);

// ---- archive awareness (v0.9.0): feature_archive.json shares the id namespace ----
// Reusing an archived id would corrupt history references (progress.md entries, evidence,
// commit messages all key on it), so both modes treat archived ids as taken. A corrupt
// archive is a hard error — silently ignoring it would disable the uniqueness guard.
const archivePath = join(dirname(path), 'feature_archive.json');
let archivedIds = new Set();
let archRaw = null;
try { archRaw = readFileSync(archivePath, 'utf8'); } catch { /* no archive — normal */ }
if (archRaw !== null) {
    let archData;
    try {
        archData = JSON.parse(archRaw);
    } catch (err) {
        console.error(`feature-list-validate: invalid JSON in ${archivePath}: ${err && err.message ? err.message : err}`);
        exit(1);
    }
    const archFeatures = (archData && Array.isArray(archData.features)) ? archData.features : [];
    archivedIds = new Set(archFeatures
        .map(f => (f && typeof f.id === 'string') ? f.id : null)
        .filter(id => id !== null));
}

const existing = new Set([...ids, ...archivedIds]);

/** First free `<stem>-<N>` id across hot + archive; bumps a trailing -N rather than stacking. */
function suggest(base) {
    const m = base.match(/^(.*?)-(\d+)$/);
    const stem = m ? m[1] : base;
    let n = m ? parseInt(m[2], 10) + 1 : 2;
    while (existing.has(`${stem}-${n}`)) n++;
    return `${stem}-${n}`;
}

if (checkId !== null) {
    // ---- --check mode: is this candidate already taken (hot OR archived)? ----
    if (existing.has(checkId)) {
        const where = ids.includes(checkId) ? '' : ' (in feature_archive.json — archived ids stay reserved)';
        console.log(`id '${checkId}' already exists${where}; try '${suggest(checkId)}'`);
        exit(3);
    }
    exit(0);
}

// ---- default mode: duplicates within the hot file, and hot∩archive collisions ----
const counts = new Map();
for (const id of ids) counts.set(id, (counts.get(id) || 0) + 1);
const dups = [...counts.entries()].filter(([, n]) => n > 1);
const cross = [...new Set(ids)].filter(id => archivedIds.has(id));

let bad = false;
if (dups.length > 0) {
    const listed = dups.map(([id, n]) => `'${id}' (×${n})`).join(', ');
    console.log(`Duplicate feature id(s): ${listed}. Feature ids must be unique — they key status/evidence updates. Rename the newer entry to a unique id.`);
    bad = true;
}
if (cross.length > 0) {
    const listed = cross.map(id => `'${id}'`).join(', ');
    console.log(`Feature id(s) also present in feature_archive.json: ${listed}. Archived ids stay reserved — rename the hot entry (the archive is read-only history), e.g. '${suggest(cross[0])}'.`);
    bad = true;
}
exit(bad ? 3 : 0);
