#!/usr/bin/env node
/**
 * feature-list-sort.mjs — Reorder feature_list.json `features` "actionable-first".
 *
 * Order: in-progress → blocked → planned → (unknown) → pass (pass last). Stable within a
 * group: non-pass by `createdAt` ascending; pass by `completedAt` descending; final
 * tie-break = original array index, so the sort is deterministic AND idempotent.
 *
 * Reorders the `features` array ONLY. Every other top-level key (including unknown extras
 * the schema permits), each feature's key order, 2-space indentation and the trailing
 * newline are preserved — so a re-sort produces *only* an array-order diff, never silent
 * field loss or formatting churn.
 *
 * Usage:  node feature-list-sort.mjs [path/to/feature_list.json]   (default ./feature_list.json)
 * Exit:   0 on success or harmless no-op; 1 on hard error (missing file / invalid JSON).
 *
 * Best-effort by design: /session-end ignores a non-zero exit and leaves order unchanged.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { argv, exit } from 'node:process';

const path = argv[2] || 'feature_list.json';

// Actionable-first rank. Unknown statuses sort just before `pass` (visible, not buried).
const RANK = { 'in-progress': 0, blocked: 1, planned: 2, pass: 4 };
const UNKNOWN_RANK = 3;

function rankOf(status) {
    return Object.prototype.hasOwnProperty.call(RANK, status) ? RANK[status] : UNKNOWN_RANK;
}

try {
    let raw;
    try {
        raw = readFileSync(path, 'utf8');
    } catch {
        console.error(`feature-list-sort: cannot read ${path}`);
        exit(1);
    }

    const data = JSON.parse(raw); // throws on invalid JSON → caught below

    if (!data || !Array.isArray(data.features) || data.features.length < 2) {
        // Nothing to reorder — leave the file byte-for-byte untouched.
        exit(0);
    }

    // Decorate with original index for a stable, deterministic final tie-break.
    const decorated = data.features.map((feat, i) => ({ feat, i }));

    decorated.sort((a, b) => {
        const ra = rankOf(a.feat && a.feat.status);
        const rb = rankOf(b.feat && b.feat.status);
        if (ra !== rb) return ra - rb;

        // Same group: pass → newest completedAt first; others → oldest createdAt first.
        if (ra === RANK.pass) {
            const ca = a.feat.completedAt || '';
            const cb = b.feat.completedAt || '';
            if (ca !== cb) return ca < cb ? 1 : -1; // desc
        } else {
            const ca = a.feat.createdAt || '';
            const cb = b.feat.createdAt || '';
            if (ca !== cb) return ca < cb ? -1 : 1; // asc
        }
        return a.i - b.i; // stable final tie-break
    });

    data.features = decorated.map(d => d.feat);

    writeFileSync(path, JSON.stringify(data, null, 2) + '\n');
    exit(0);
} catch (err) {
    console.error(`feature-list-sort: ${err && err.message ? err.message : err}`);
    exit(1);
}
