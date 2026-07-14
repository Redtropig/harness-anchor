---
description: Show current project status — active feature, feature counts, git tree, TOC freshness, session handoff. Read-only overview. Distinct from /session-end (which writes).
allowed-tools: Bash, Read
---

# /status

Read-only project status overview. The report body is produced by a script —
`scripts/status-report.sh` is the **single source of truth** for its sections
and formatting (all 7: Status header / Active feature / Feature counts /
Git working tree / TOC freshness / Session handoff head / Harness health).

## Steps

1. **Run the report script:**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/status-report.sh --target "$(pwd)"
   ```

2. **Print its output verbatim.** Do not reformat, reorder, or summarize — the
   sections are the contract (tests pin them).

3. **Append at most ONE suggestion line** when the report warrants it:
   - `Project not anchored…` → suggest `/anchor`
   - a state-budget entry carries `OVER` → point at `/session-end` (archival)
   - TOC freshness is `absent` or `stale` → mention `/index-project`

   One line, only when applicable — the report already carries its facts.

## If the script fails

Report the script's error output verbatim first. Because /status is read-only,
you MAY then degrade to a minimal manual snapshot (head of `feature_list.json`,
`git status --porcelain`) — say explicitly that this is the degraded path.
This is the only thin-wrapper command with a manual fallback; the others
(/anchor, /cpp-init, /session-end) write state and must not be hand-replayed.

## Boundary with /session-end

- `/status` is **read-only**. It never writes `feature_list.json`,
  `progress.md`, or `session-handoff.md`.
- `/session-end` **writes** handoff + progress + offers commit. Use it at the
  end of a session.
- Use `/status` anytime you want a quick "where am I?" snapshot.
