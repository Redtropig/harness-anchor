# Context Budget Template

Use this format in `context-budget.md` (scaffolded by `/anchor`) to track per-session context allocation.

## Default budget table

| Block | Source | Tier | Budget | Current | Status |
|---|---|---|---|---|---|
| superpowers system context | superpowers SessionStart | 1 | ~1500 t | — | always on; its own budget, **outside** the harness-anchor cap below |
| harness-anchor injection (= the three parts below) | this plugin SessionStart | 1 | **≤3000 t (12000-char hard cap); measured at v0.10.0: generic ≈1160 t / C/C++ ≈1580 t** | — | headroom is deliberate — it belongs to the TOC block |
| ├ state banner | `<harness-anchor-state>` block | 1 | ~150 t | — | active feature, project type, TOC freshness, golden-rules count, state-budget sentinel, handoff head (10 lines) |
| ├ TOC view | `<project-toc>` adaptive block | 1 | leftover-sized (~1700 t available on a generic project) | — | full `## Files` → `## Directory map` → top-level dirs, as budget allows |
| └ meta-skill body | using-harness-anchor SKILL.md | 1 | ~1050 t generic / ~1200 t C/C++ | — | injected slimmed (no frontmatter; cpp-only + os-<name> regions gated); truncated last if the cap would be exceeded |
| Loaded skills (on demand) | Skill tool | 2 | ~1000-3000 t each (largest ≈2800 at v0.9.0) | varies | unloaded when not in use |
| Reference docs | skill subdirectories | 3 | varies | varies | loaded by Read |
| Working context | file reads, edits, command outputs | — | model window − the always-on blocks | varies | the big variable |

## Watch points

- **PROJECT-TOC.md outgrows the leftover budget** → the SessionStart hook degrades adaptively (full `## Files` → `## Directory map` → top-level dirs only, with a pointer to the full file). Nothing is lost — `Grep` the `## Files` section on demand; never full-read a large TOC.
- **A `State budget:` line appears in the banner** → a state file exceeded its cap (progress 64KB · feature_list 32KB · golden-rules 8KB · AGENTS 8KB · handoff 4KB); `/session-end` offers archival/trim.
- **session-handoff.md grows beyond 10 lines** → its first 10 lines should be the most important. Keep "next action" at the top.
- **Loaded skills accumulate** → if you've loaded >3 skills this session, consider whether they're all still relevant.
- **A pulse watermark line appears** (`Context is filling` / `heavily filled`) → T1: flush chat-only durable memory; T2: prefer `/session-end` + a fresh session over auto-compaction.

## Compaction trigger checklist

Before triggering compaction:

- [ ] Have I written everything important to disk (handoff, progress)?
- [ ] Have I captured evidence paths for current work?
- [ ] Am I at a natural feature boundary, or mid-feature?

If mid-feature: **prefer `/session-end` + fresh context** over compaction (per Anthropic Nov 2025).

## Estimating without a meter

You don't have a precise token counter inside the session. Heuristics:

- A reply you wrote ≈ # chars / 4 tokens
- A file you read = chars / 4 tokens
- An edit ≈ size of new content (the diff is mostly free for the model)
- A subagent dispatch returns a fixed-size report (typically <1000 tokens)

When the user asks "how much room do we have?", be honest: *"I estimate we're around 30-40% used, primarily from <main contributor>. To get precise numbers, check the Claude Code status bar."*
