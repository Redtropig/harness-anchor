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
   - **Verify id uniqueness before committing:** `node ${CLAUDE_PLUGIN_ROOT}/scripts/feature-list-validate.mjs feature_list.json` (best-effort; skip silently if node is unavailable). If it exits non-zero, it prints the duplicate id(s) — resolve by **renaming the newer entry** to the suggested unique id (never rename an existing id, never commit a colliding ledger) before step 9.

6. **State-file budget check (archival offer).** Run `node ${CLAUDE_PLUGIN_ROOT}/scripts/state-archive.mjs --dry-run` (best-effort — skip silently if node is unavailable). If the output is `nothing to archive`, move on without comment. Otherwise it reports the backlog (progress.md sections beyond the newest 20; `pass` features beyond the 10 most recently completed) — ask the user:

   *"State files exceed their hot windows: <dry-run report>. Archive the excess now? It is moved verbatim — evidence intact — to git-tracked `progress-archive.md` / `feature_archive.json`; history is never deleted."* (Archive / Skip)

   - **Archive** → run the same command without `--dry-run`, then re-run `feature-list-validate.mjs` (it cross-checks archived ids). Include both archive files in step 9's state-file commit.
   - **Skip** → if the overage is large, note it in the handoff's Risks. Never archive without confirmation; never edit archive files by hand.
   - Housekeeping (informational only, no action): if `.harness-anchor/` exceeds ~5MB, mention that old `drift-*` / `coverage-*` / `sanitize-*` logs there are gitignored evidence and can be deleted freely.

7. **Flywheel reflection (capture the session's lessons).** Ask one quick question — *"Did anything recur this session that should change a shared artifact (a golden rule, a convention, or a skill)?"*
   - If yes and it's a **failure / anti-pattern** → capture it as a `GR-<n>` in `golden-rules.md` via the `capturing-golden-rules` skill. Route other signals to their home (a missing fact → AGENTS.md; a reliable prompt / workflow → a skill or AGENTS.md).
   - Usually the answer is no — say so and move on. This is a few-seconds reflex anchored to session-end (the feedback flywheel), **not** a ceremony.

8. **Offer TOC refresh.** If git diff suggests structural changes (new/renamed/deleted files), ask the user:

   *"Project structure changed. Refresh PROJECT-TOC.md now?"* (Yes / Skip)

9. **Surface uncommitted source, then offer the state-file commit.**

   a. **Full-tree scan (not just state files).** Run `git status --short` over the *whole* tree. If any source / test / build files beyond the harness state files are modified or untracked, list them and tell the user:

      *"⚠️ Uncommitted source/test changes: <files>. A feature marked `pass` whose source isn't committed leaves the committed HEAD not reflecting your evidence — commit them (your call) before relying on this `pass`."*

      Do **not** assert any uncommitted change is "old / unrelated / from a prior task" without running `git diff -- <file>` first — that misjudgment is exactly how a `pass`'s own source gets left behind.

   b. **HEAD-buildability caveat.** If the tree is dirty, note that the verification evidence reflects the **working tree**, not the committed `HEAD`. To prove the committed state reproduces green, recommend (do not run) a throwaway checkout: `git worktree add --detach /tmp/ha-head HEAD && <configure cmd> /tmp/ha-head` — a configure/build failure (e.g. a missing committed source file) means HEAD is broken even though the working tree builds.

   c. **Offer the state-file commit.** Show `git status` of the state files (handoff/progress/feature_list/TOC). Ask: *"Commit these state changes?"* (Yes / I'll commit later / Show diff). If Yes: stage the **state files only** and commit with message `chore(harness): session N handoff — <active feature id>`. **Do not auto-commit source** — surfacing it in (a) is the help; committing it stays the user's call.

## Scope — a session-pause checkpoint, not branch completion

`/session-end` only **persists harness state** (handoff / progress / feature_list / TOC) and may commit **those state files**. It deliberately does not handle code integration. When the *feature or branch itself* is finished — merge, PR, worktree cleanup, or discard — that is **`superpowers:finishing-a-development-branch`** (preceded by `requesting-code-review`). They compose cleanly: finish the branch with superpowers, then run `/session-end` to record the handoff. The Stop-hook nudge for `/session-end` is about checkpointing a pause, not a substitute for that branch-completion flow.

## Why these steps in this order

- Verification before handoff so the handoff reflects ground truth, not optimism.
- Handoff before progress.md so the "right-now" snapshot is current first.
- feature_list.json status change last so it depends on the evidence collected.
- Budget check after the ledger update so features passed *this* session count toward the pass window — and before the commit so the archives ride the same state-file commit.
- TOC and commit are optional; do not block on them.

## Refusal cases

If `feature_list.json` is missing → suggest `/anchor` first. The user might be in an un-anchored project.

If the user wants to mark `status='pass'` but evidence is incomplete → **refuse** and state which evidence is missing. This is the Default-FAIL contract.
