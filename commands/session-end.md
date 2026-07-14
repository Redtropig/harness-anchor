---
description: Guided end-of-session ritual. Writes structured handoff (session-handoff.md), appends progress.md entry, and offers over-budget state archival + TOC refresh + git commit.
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion
---

# /session-end

End the current session cleanly (the "clean restart path" lifecycle pattern).
The mechanical gathering is ONE script call; every judgment step below
consumes its facts.

## Steps

1. **Gather the facts:**

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/session-end-precheck.sh --target "$(pwd)"
   ```

   The block reports: active feature + counts · init.sh result (60s cap;
   `--skip-init` only if the user explicitly asks) · archival backlog
   (state-archive dry-run) · ledger validation · working tree in two columns
   (state files / source) · TOC structural changes since anchor.
   If the script fails, report its error verbatim and stop — do not
   hand-replay the gathering (writes follow it; only /status may degrade).

2. **If no active feature** (block says so), ask: *"No active feature. What
   were we working on this session?"* — use the answer for the progress entry.

3. **Write `session-handoff.md`** (overwrite). Fields: ISO-8601 UTC timestamp ·
   active feature id · what's in flight (2-5 bullets) · build/test/lint state
   (from the init.sh fact + this session's runs, with timestamps) · **next
   session's first action** (ONE concrete thing — the most important field) ·
   risks. Keep ≤ 300 words.

4. **Prepend the `progress.md` entry.** Compose the section (template shape:
   `## YYYY-MM-DD HH:MM — Session N`, Accomplished / Files changed / Evidence
   collected / Remaining / Decisions / Next first action), then prefer
   `node ${CLAUDE_PLUGIN_ROOT}/scripts/progress-prepend.mjs progress.md <entry-file>`;
   fall back to Read+prepend+Write only if node is unavailable.

5. **Update `feature_list.json` if applicable** — Default-FAIL:
   - All criteria met **with evidence** → status='pass', evidence object, completedAt.
   - Blocked → status='blocked' + blockedReason. Otherwise leave in-progress.
   - Then `node ${CLAUDE_PLUGIN_ROOT}/scripts/feature-list-sort.mjs feature_list.json`
     (best-effort). If step 1's ledger fact reported duplicate ids, resolve by
     renaming the NEWER entry per its suggestion before committing.

6. **Archival (consent-gated).** Step 1's backlog fact is the dry-run. If it
   reported a backlog, ask: *"State files exceed their hot windows: <facts>.
   Archive the excess now? Moved verbatim — evidence intact — to git-tracked
   archives; history is never deleted."* (Archive / Skip)
   - Archive → `node ${CLAUDE_PLUGIN_ROOT}/scripts/state-archive.mjs --target "$(pwd)"`,
     then re-run `feature-list-validate.mjs`; include archives in step 9's commit.
   - Skip → large overage goes into the handoff's Risks. Never archive without
     consent; never hand-move entries (if the fact line says archival needs
     Node, relay that and move on).
   - Non-archivable overages (golden-rules.md / AGENTS.md over 8KB): archival
     does not apply — golden-rules wants pruning (step 7's flywheel;
     `capturing-golden-rules`), AGENTS.md wants thinning back to a map.
     An oversized handoff self-heals at step 3 if you keep it ≤ 300 words.

7. **Flywheel reflection.** Ask once: *"Did anything recur this session that
   should change a shared artifact (a golden rule, a convention, or a skill)?"*
   Failure/anti-pattern → `capturing-golden-rules`; a missing fact → AGENTS.md;
   a reliable workflow → a skill or AGENTS.md. Usually the answer is no —
   move on; this is a reflex, not a ceremony.

8. **Offer TOC refresh** if step 1's structural-change fact is non-empty:
   *"Project structure changed. Refresh PROJECT-TOC.md now?"* (Yes / Skip)

9. **Surface uncommitted source, then offer the state-file commit.**
   - The two-column tree fact is the evidence. If source/other is non-clean,
     warn: a feature marked `pass` whose source isn't committed leaves HEAD
     not reflecting the evidence. Do NOT declare any change "old / unrelated"
     without `git diff -- <file>` first.
   - If the tree is dirty, note the verification evidence reflects the
     **working tree**, not HEAD. To prove HEAD, recommend (do not run):
     `git worktree add --detach /tmp/ha-head HEAD && <configure cmd> /tmp/ha-head`.
   - Ask: *"Commit these state changes?"* (Yes / Later / Show diff). On Yes,
     stage the **state-file column only** (plus archives if step 6 archived)
     and commit as `chore(harness): session N handoff — <active feature id>`.
     Never auto-commit source.

## Scope — a session-pause checkpoint, not branch completion

`/session-end` only persists harness state and may commit those state files.
When the feature/branch itself is finished — merge, PR, cleanup — that is
`superpowers:finishing-a-development-branch` (preceded by
`requesting-code-review`). Finish the branch with superpowers, then run
`/session-end` to record the handoff.

## Why this order

Facts before writing (the handoff reflects ground truth, not optimism);
handoff before progress (the "right now" snapshot first); ledger flip last
among writes (it depends on evidence); archival after the flip (this
session's passes count toward the window) and before the commit (archives
ride the same commit); TOC and commit are optional — never block on them.

## Refusal cases

- No `feature_list.json` → suggest `/anchor` first.
- User wants `status='pass'` with incomplete evidence → **refuse** and name
  the missing evidence. This is the Default-FAIL contract.
