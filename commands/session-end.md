---
description: Guided end-of-session ritual. Writes structured handoff (session-handoff.md), appends progress.md entry, and offers TOC refresh + git commit.
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion
---

# /session-end

End the current session cleanly. Implements the "clean restart path" lifecycle pattern from learn-harness L12.

## Steps

1. **Check active feature.** Read `feature_list.json`, identify the entry with `status: "in-progress"`.

   - If none, ask the user: *"No active feature. What were we working on this session? (free text)"*. Use the answer for the progress entry.

2. **Run verification.** If `init.sh` exists, run it and capture the result (pass/fail). Note in handoff.

3. **Update `session-handoff.md`** (overwrite). Fields:
   - Timestamp (ISO 8601 UTC)
   - Active feature id
   - **What's in flight** — 2-5 bullets from the user's accomplishments this session
   - **Build/test/lint state** — most recent run for each, with timestamp
   - **Next session's first action** — ONE concrete thing (this is the most important field)
   - **Risks** — anything fragile or being worked around

   Keep ≤ 300 words.

4. **Append to `progress.md`**. **Prepend** a new section (most recent first). Prefer `node ${CLAUDE_PLUGIN_ROOT}/scripts/progress-prepend.mjs progress.md <entry-file>` — it inserts after the header without loading the whole file (cheap on a long history); fall back to Read+prepend+Write if node is unavailable. Section structure:

   ```
   ## YYYY-MM-DD HH:MM — Session N
   **Active feature**: ...
   **Status when session started**: ...
   **Status when session ended**: ...

   ### Accomplished
   ### Files changed
   ### Evidence collected
   ### Remaining for active feature
   ### Decisions made
   ### Next session's first action
   ```

5. **Update `feature_list.json` if applicable**:
   - If criteria all met with evidence → status='pass', evidence object populated, completedAt set
   - If blocked → status='blocked', blockedReason populated
   - Otherwise → leave status='in-progress'
   - Then keep entries actionable-first: `node ${CLAUDE_PLUGIN_ROOT}/scripts/feature-list-sort.mjs feature_list.json` (best-effort, deterministic reorder only — skip silently if node is unavailable).

6. **Offer TOC refresh.** If git diff suggests structural changes (new/renamed/deleted files), ask the user:

   *"Project structure changed. Refresh PROJECT-TOC.md now?"* (Yes / Skip)

7. **Offer commit.** Show `git status` of the state files (handoff/progress/feature_list/TOC). Ask:

   *"Commit these state changes?"* (Yes / I'll commit later / Show diff)

   If Yes: stage the state files only and commit with message: `chore(harness): session N handoff — <active feature id>`. **Do not commit source code changes** — those are the user's call.

## Scope — a session-pause checkpoint, not branch completion

`/session-end` only **persists harness state** (handoff / progress / feature_list / TOC) and may commit **those state files**. It deliberately does not handle code integration. When the *feature or branch itself* is finished — merge, PR, worktree cleanup, or discard — that is **`superpowers:finishing-a-development-branch`** (preceded by `requesting-code-review`). They compose cleanly: finish the branch with superpowers, then run `/session-end` to record the handoff. The Stop-hook nudge for `/session-end` is about checkpointing a pause, not a substitute for that branch-completion flow.

## Why these steps in this order

- Verification before handoff so the handoff reflects ground truth, not optimism.
- Handoff before progress.md so the "right-now" snapshot is current first.
- feature_list.json status change last so it depends on the evidence collected.
- TOC and commit are optional; do not block on them.

## Refusal cases

If `feature_list.json` is missing → suggest `/anchor` first. The user might be in an un-anchored project.

If the user wants to mark `status='pass'` but evidence is incomplete → **refuse** and state which evidence is missing. This is the Default-FAIL contract.
