---
description: Show current project status — active feature, feature counts, git tree, TOC freshness, session handoff. Read-only overview. Distinct from /session-end (which writes).
allowed-tools: Bash, Read
---

# /status

Read-only project status overview. Shows everything at a glance without modifying any files. Distinct from `/session-end` which *writes* handoff + progress.

## Output sections (fixed order)

1. **`## Status — <project>`** — project name from `feature_list.json` or directory name
2. **`### Active feature`** — the `in-progress` entry from `feature_list.json`, or "(none)"
3. **`### Feature counts`** — planned / in-progress / pass / blocked tallies
4. **`### Git working tree`** — output of `git status --porcelain` (or "not a git repo")
5. **`### TOC freshness`** — output of `scripts/toc-freshness.sh` (fresh / stale / absent / no-anchor / not-git)
6. **`### Session handoff (head)`** — first 15 lines of `session-handoff.md`, or "(no handoff file)"
7. **`### Harness health`** — golden-rules count, last `/gc` drift-scan age + verdict, active-feature staleness, handoff age

## Steps

1. **Read `feature_list.json`.** If it doesn't exist, report "Project not anchored — run `/anchor` first" and stop.

   Use Python3 to extract the project name, active feature, and status counts:
   ```python
   import json
   with open('feature_list.json') as f:
       data = json.load(f)
   project = data.get('project', '(unnamed)')
   active = next((f for f in data.get('features', []) if f.get('status') == 'in-progress'), None)
   counts = {}
   for f in data.get('features', []):
       s = f.get('status', 'unknown')
       counts[s] = counts.get(s, 0) + 1
   ```

2. **Print header and active feature.**
   ```
   ## Status — <project>
   ### Active feature
   - **<id>**: <name> (<description>) — status: in-progress
   ```
   Or if no active feature: `(no in-progress feature)`

3. **Print feature counts.**
   ```
   ### Feature counts
   - planned: N
   - in-progress: N
   - pass: N
   - blocked: N
   ```

4. **Print git working tree.** Run `git status --porcelain`. If not in a git repo, say so.

5. **Print TOC freshness.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/toc-freshness.sh <project-dir>` and print the output directly.

6. **Print session handoff head.** Read first 15 lines of `session-handoff.md`. If missing, say "(no session-handoff.md — run `/session-end` after work)".

7. **Print harness health.** A few counts/ages — **not** a metrics dashboard. Read the *last persisted* drift report; never run a scan (that is `/gc`'s job).

   ```
   ### Harness health
   - golden rules: N        (grep -c '^### GR-' golden-rules.md; else "(none — seed via capturing-golden-rules)")
   - last /gc scan: <age of newest .harness-anchor/drift-*.md> — <verdict if parseable>   (else "never — run /gc")
   - active feature age: <now − createdAt of the in-progress feature>   (else "(no active feature)")
   - handoff age: <now − mtime of session-handoff.md>   (else "(no handoff)")
   ```

## Boundary with /session-end

- `/status` is **read-only**. It never writes to `feature_list.json`, `progress.md`, or `session-handoff.md`.
- `/session-end` **writes** handoff + progress + offers commit. Use it at the end of a session.
- Use `/status` anytime you want a quick "where am I?" snapshot.
