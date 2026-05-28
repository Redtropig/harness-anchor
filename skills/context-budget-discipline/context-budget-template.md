# Context Budget Template

Use this format in `context-budget.md` (scaffolded by `/anchor`) to track per-session context allocation.

## Default budget table

| Block | Source | Tier | Budget | Current | Status |
|---|---|---|---|---|---|
| superpowers system context | superpowers SessionStart | 1 | ~1500 t | — | always on |
| harness-anchor system context | this plugin SessionStart | 1 | ~700 t | — | always on |
| Active feature state | feature_list.json extract | 1 | ~50 t | — | depends on # features |
| PROJECT-TOC head | PROJECT-TOC.md (first ~30 entries) | 1 | ~500 t | — | grows with project |
| Session handoff head | session-handoff.md (first 10 lines) | 1 | ~150 t | — | constant |
| **Tier 1 total** | | 1 | **≤2000 t** | | hard cap at hook output |
| Loaded skills (on demand) | Skill tool | 2 | ~1000-3000 t each | varies | unloaded when not in use |
| Reference docs | skill subdirectories | 3 | varies | varies | loaded by Read |
| Working context | file reads, edits, command outputs | — | model window - 2000 | varies | the big variable |

## Watch points

- **PROJECT-TOC.md exceeds 1500 tokens** → SessionStart hook truncates with pointer to full file. Still in your filesystem; you can `Read` it explicitly when needed.
- **session-handoff.md grows beyond 10 lines** → its first 10 lines should be the most important. Keep "next action" at the top.
- **Loaded skills accumulate** → if you've loaded >3 skills this session, consider whether they're all still relevant.

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
