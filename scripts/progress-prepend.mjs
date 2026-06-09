#!/usr/bin/env node
/**
 * progress-prepend.mjs — Insert a new entry at the top of progress.md (most-recent-first)
 * WITHOUT the caller loading the whole file into context.
 *
 * The new entry is inserted immediately after the header block — defined as everything up
 * to and including the FIRST `---` line (the template's title + blockquote + separator).
 * All existing entries follow, untouched (append-only history is never rewritten or dropped).
 * If no `---` separator exists, the entry is prepended at the very top — never corrupt the file.
 *
 * Usage:
 *   node progress-prepend.mjs <progress.md> <entry-file>   (entry read from a file)
 *   node progress-prepend.mjs <progress.md> -              (entry read from stdin)
 * Exit: 0 on success; 1 on hard error (missing target / empty or unreadable entry).
 *
 * Best-effort by design: /session-end falls back to a manual Read+prepend+Write on non-zero.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { argv, exit } from 'node:process';

const target = argv[2];
const entrySrc = argv[3];

if (!target || !entrySrc) {
    console.error('usage: progress-prepend.mjs <progress.md> <entry-file|->');
    exit(1);
}

function readEntry() {
    try {
        return readFileSync(entrySrc === '-' ? 0 : entrySrc, 'utf8'); // fd 0 = stdin
    } catch {
        return null;
    }
}

try {
    const rawEntry = readEntry();
    if (rawEntry === null) {
        console.error(`progress-prepend: cannot read entry from ${entrySrc}`);
        exit(1);
    }
    const entry = rawEntry.trim();
    if (!entry) {
        console.error('progress-prepend: empty entry; nothing to do');
        exit(1);
    }

    let body;
    try {
        body = readFileSync(target, 'utf8');
    } catch {
        console.error(`progress-prepend: cannot read ${target}`);
        exit(1);
    }

    const lines = body.split('\n');
    const sep = lines.findIndex(l => l.trim() === '---');

    let output;
    if (sep === -1) {
        // No header separator — prepend at the very top; keep the rest verbatim.
        output = `${entry}\n\n${body.replace(/^\n+/, '')}`;
    } else {
        const header = lines.slice(0, sep + 1).join('\n');                 // through the first ---
        const rest = lines.slice(sep + 1).join('\n').replace(/^\n+/, '');  // drop leading blanks
        output = `${header}\n\n${entry}\n\n${rest}`;
    }

    // Normalize to exactly one trailing newline.
    output = output.replace(/\n*$/, '\n');

    writeFileSync(target, output);
    exit(0);
} catch (err) {
    console.error(`progress-prepend: ${err && err.message ? err.message : err}`);
    exit(1);
}
