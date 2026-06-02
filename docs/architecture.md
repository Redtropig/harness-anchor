<!-- doc-align: 9801eacb02d6fd316829be3b56b8af1bc31cc809 · 2026-06-03 · harness-anchor v0.3.2 -->
# harness-anchor — Component Relationship Graph

> **Aligned with commit** [`9801eac`](https://github.com/Redtropig/harness-anchor/commit/9801eacb02d6fd316829be3b56b8af1bc31cc809) (harness-anchor v0.3.2, 2026-06-03). Verified against the plugin sources — `hooks/`, `commands/`, `skills/`, `agents/`, `scripts/`, `templates/` — at this commit; re-verify and bump this marker if they change.

How the plugin's components (**hooks · commands · skills · agents · scripts · templates**) call
and trigger one another, with **trigger conditions**, **effects**, and the **state/info** each
needs. Diagrams are [Mermaid](https://mermaid.js.org) (render on GitHub).

## The one idea to hold onto

harness-anchor has **three invocation modes** that all converge on **one shared state substrate**
(per-project files on disk):

| Mode | Who fires it | Examples | Can it write state? |
|---|---|---|---|
| ① **Automatic** | Claude Code *events* → warn-only hooks | SessionStart, PostToolUse, Stop, UserPromptSubmit | **No** — hooks only *read* state + *recommend* commands |
| ② **Model-pulled** | the agent *auto-loads* a skill by its description; a skill may dispatch a subagent via `Task` | 12 skills, 3 agents | Agents: only `index-curator` writes (`PROJECT-TOC.md`); the rest are read-only |
| ③ **User-invoked** | the user types a *slash command* | `/anchor` … `/session-end` | **Yes** — commands are the main writers |

Hooks are deliberately "dumb": they detect a situation and *nudge* the user toward a command or
surface context. The actual work (writing state, running tools, sanitizers) lives in **commands**
and **subagents**. This keeps every hook **warn-only and ≤ 5 s** (design invariants #1, #7).

### Legend

```mermaid
flowchart LR
  E["event"]:::evt --> Hk["hook"]:::hook
  Cm["command"]:::cmd
  Sk["skill"]:::skill
  Ag["agent"]:::agent
  Sc["script"]:::script
  Tp["template"]:::tpl
  St[("state file")]:::state
  Hk -.->|"recommend (warn-only, dashed)"| Cm
  Cm -->|"call / write (solid)"| St
  classDef evt fill:#ffe0ef,stroke:#c2185b,color:#000
  classDef hook fill:#fff0d0,stroke:#ef6c00,color:#000
  classDef cmd fill:#d7ecff,stroke:#0277bd,color:#000
  classDef skill fill:#d9f5d9,stroke:#2e7d32,color:#000
  classDef agent fill:#ece3ff,stroke:#6a1b9a,color:#000
  classDef script fill:#f5f0d0,stroke:#9e8a00,color:#000
  classDef tpl fill:#e8e8e8,stroke:#616161,color:#000
  classDef state fill:#fafafa,stroke:#9e9e9e,color:#000,stroke-dasharray:4 3
```

- **Solid arrow** = direct call / invoke / write.
- **Dashed arrow** = warn-only *recommendation* (the component only suggests; the user/agent acts).

---

## 1 · Master overview

```mermaid
flowchart TB
  classDef evt fill:#ffe0ef,stroke:#c2185b,color:#000
  classDef hook fill:#fff0d0,stroke:#ef6c00,color:#000
  classDef cmd fill:#d7ecff,stroke:#0277bd,color:#000
  classDef skill fill:#d9f5d9,stroke:#2e7d32,color:#000
  classDef agent fill:#ece3ff,stroke:#6a1b9a,color:#000
  classDef script fill:#f5f0d0,stroke:#9e8a00,color:#000
  classDef tpl fill:#e8e8e8,stroke:#616161,color:#000
  classDef state fill:#fafafa,stroke:#9e9e9e,color:#000,stroke-dasharray:4 3

  subgraph AUTO["① AUTOMATIC (Claude Code events)"]
    EV["SessionStart · PostToolUse · Stop · UserPromptSubmit"]:::evt
    RUN["run-hook.cmd<br/>(polyglot cmd/bash wrapper)"]:::script
    HOOKS["4 warn-only hooks"]:::hook
    EV --> RUN --> HOOKS
  end

  subgraph PULL["② MODEL-PULLED (auto-load by description)"]
    META["using-harness-anchor<br/>(meta-skill)"]:::skill
    SKILLS["11 sibling skills<br/>(docs-lookup is the hub)"]:::skill
    AGENTS["3 subagents via Task<br/>(single-level)"]:::agent
    META --- SKILLS
    SKILLS -->|"dispatch"| AGENTS
  end

  subgraph USER["③ USER-INVOKED (slash commands)"]
    CMDS["/anchor /cpp-init /index-project<br/>/verify /sanitize /status /session-end"]:::cmd
  end

  HELP["runtime scripts<br/>cpp-detect · toc-freshness · index-builder"]:::script
  TPL["templates/*.tpl"]:::tpl
  STATE[("PER-PROJECT STATE<br/>feature_list.json · progress.md · session-handoff.md<br/>PROJECT-TOC.md · AGENTS.md · init.sh · context-budget.md<br/>.clang-format/.clang-tidy · .harness-anchor/ logs")]:::state

  HOOKS -->|"read"| STATE
  HOOKS -->|"call"| HELP
  HOOKS -->|"SessionStart injects banner + meta-skill body"| META
  HOOKS -.->|"recommend"| CMDS
  SKILLS -.->|"recommend"| CMDS
  CMDS -->|"call"| HELP
  CMDS -->|"Task"| AGENTS
  CMDS -->|"instantiate"| TPL
  CMDS -->|"write"| STATE
  TPL -->|"produce"| STATE
  HELP -->|"build index / detect / freshness"| STATE
  AGENTS -->|"evidence report / write PROJECT-TOC.md"| STATE
```

---

## 2 · Automatic layer — the 4 hooks

All four are registered in `hooks/hooks.json`, dispatched through `hooks/run-hook.cmd`, and are
**warn-only**: they emit `additionalContext` (or `systemMessage` for Stop) and **never block**.

```mermaid
flowchart LR
  classDef evt fill:#ffe0ef,stroke:#c2185b,color:#000
  classDef hook fill:#fff0d0,stroke:#ef6c00,color:#000
  classDef cmd fill:#d7ecff,stroke:#0277bd,color:#000
  classDef script fill:#f5f0d0,stroke:#9e8a00,color:#000
  classDef state fill:#fafafa,stroke:#9e9e9e,color:#000,stroke-dasharray:4 3

  SS(["SessionStart<br/>matcher: startup|clear|compact"]):::evt
  PTU(["PostToolUse<br/>matcher: Edit|Write"]):::evt
  STOP(["Stop"]):::evt
  UPS(["UserPromptSubmit"]):::evt

  Hs["hooks/session-start"]:::hook
  Hp["hooks/post-tool-use"]:::hook
  Ht["hooks/stop"]:::hook
  Hu["hooks/user-prompt-submit"]:::hook

  SS --> Hs
  PTU --> Hp
  STOP --> Ht
  UPS --> Hu

  cpd["cpp-detect.sh"]:::script
  tocf["toc-freshness.sh"]:::script

  fl[("feature_list.json")]:::state
  pm[("progress.md")]:::state
  sh[("session-handoff.md")]:::state
  toc[("PROJECT-TOC.md")]:::state
  cc[("compile_commands.json")]:::state

  %% session-start
  Hs -->|"call"| cpd
  Hs -->|"call"| tocf
  Hs -->|"read active feature"| fl
  Hs -->|"read head"| sh
  tocf -->|"freshness vs git"| toc
  Hs -.->|"un-anchored ⇒ /anchor"| A1["/anchor"]:::cmd
  Hs -.->|"C/C++ & no clang cfg ⇒ /cpp-init"| A2["/cpp-init"]:::cmd
  Hs -.->|"TOC absent/stale ⇒ /index-project"| A3["/index-project"]:::cmd

  %% post-tool-use
  Hp -->|"pass-feature file? regression-warn"| fl
  Hp -->|"present ⇒ run clang-tidy on changed C/C++"| cc
  Hp -.->|"C/C++ edit ⇒ nudge"| P1["/sanitize"]:::cmd
  Hp -.->|"before pass claim ⇒ nudge"| P2["/verify"]:::cmd

  %% stop
  Ht -->|"in-progress feature"| fl
  Ht -->|"stale >30m"| pm
  Ht -->|"stale >24h"| sh
  Ht -.->|"systemMessage reminder ⇒ /session-end"| T1["/session-end"]:::cmd

  %% user-prompt-submit
  Hu -->|"surface active feature"| fl
  Hu -.->|"scope-jump phrase (also / 顺便 / by the way)"| U1["confirm scope<br/>(one active feature)"]
```

| Hook | Fires on (trigger) | Reads (info) | Effect | Recommends |
|---|---|---|---|---|
| **session-start** | session `startup`/`clear`/`compact` | `plugin.json` (version), `feature_list.json`, `session-handoff.md`, `PROJECT-TOC.md` (via `toc-freshness.sh`), project type (via `cpp-detect.sh`), `.clang-format`/`.clang-tidy` | injects `<harness-anchor-state>` banner **+ the `using-harness-anchor` meta-skill body** (`additionalContext`, budget ≤ 2000 tok) | `/anchor` (un-anchored) · `/cpp-init` (C/C++, anchored, no clang cfg — v0.3.1) · `/index-project` (TOC absent/stale) |
| **post-tool-use** | after **Edit/Write** | `feature_list.json` (pass-feature file list), `compile_commands.json` (presence) | `additionalContext` warning: regression-warn if a *passed* feature's file changed; **clang-tidy** on the changed C/C++ file when `compile_commands.json` exists | `/sanitize` (one-line nudge on C/C++ edit) · `/verify` (before a pass claim) |
| **stop** | agent about to stop | `feature_list.json`, `progress.md` (mtime), `session-handoff.md` (mtime) | **`systemMessage`** wrap-up reminder *(v0.3.2 — was the invalid `hookSpecificOutput`)* | `/session-end` |
| **user-prompt-submit** | every user prompt | `feature_list.json` (active feature) | `additionalContext` scope-check | confirm scope before pivoting (one-active-feature) |

---

## 3 · User-invoked layer — the 7 commands

Commands are the **writers**. They call runtime scripts, instantiate templates, dispatch the
`verification-runner` subagent, and update the state files. (`allowed-tools` from each command's
frontmatter shown in the table.)

```mermaid
flowchart TB
  classDef cmd fill:#d7ecff,stroke:#0277bd,color:#000
  classDef agent fill:#ece3ff,stroke:#6a1b9a,color:#000
  classDef script fill:#f5f0d0,stroke:#9e8a00,color:#000
  classDef tpl fill:#e8e8e8,stroke:#616161,color:#000
  classDef state fill:#fafafa,stroke:#9e9e9e,color:#000,stroke-dasharray:4 3

  anchor["/anchor"]:::cmd
  cppinit["/cpp-init"]:::cmd
  index["/index-project"]:::cmd
  verify["/verify [--fix]"]:::cmd
  sanitize["/sanitize"]:::cmd
  status["/status"]:::cmd
  sessionend["/session-end"]:::cmd

  cpd["cpp-detect.sh"]:::script
  tocf["toc-freshness.sh"]:::script
  ib["index-builder.mjs"]:::script
  vr["verification-runner<br/>(fresh-context subagent)"]:::agent

  TPLbase["templates/*.tpl<br/>(AGENTS, feature_list+schema, init.sh,<br/>progress, session-handoff, PROJECT-TOC, context-budget)"]:::tpl
  TPLcpp["templates/cpp/*.tpl<br/>(.clang-format, .clang-tidy,<br/>sanitizer-build, cmake/meson-init)"]:::tpl

  state[("state files")]:::state
  log[(".harness-anchor/sanitize-*.log")]:::state

  anchor -->|"detect build system"| cpd
  anchor -->|"instantiate"| TPLbase
  TPLbase -->|"scaffold"| state

  cppinit -->|"detect"| cpd
  cppinit -->|"instantiate + tune init.sh"| TPLcpp
  TPLcpp -->|"drop .clang-format/.clang-tidy + sanitizer-build.sh"| state

  index -->|"run"| ib
  ib -->|"write PROJECT-TOC.md"| state

  verify -->|"Task (fresh each cycle)"| vr
  vr -->|"evidence report"| verify
  verify -->|"on PASS update status"| state

  sanitize -->|"gate (refuse if not C/C++)"| cpd
  sanitize -->|"use"| TPLcpp
  sanitize -->|"ASan+UBSan / TSan; report mirrors verification-runner"| log

  status -->|"freshness"| tocf
  status -->|"READ-ONLY snapshot"| state

  sessionend -->|"run init.sh; write handoff/progress/feature_list; offer commit"| state
  sessionend -.->|"offer TOC refresh"| index
```

| Command | Invoke when | Calls / dispatches | Writes (effect) | Guards / refuses |
|---|---|---|---|---|
| **/anchor** | project un-anchored (no `feature_list.json`) | `cpp-detect.sh`; instantiates **base templates** | scaffolds `AGENTS.md`, `feature_list.json`(+schema), `init.sh`, `progress.md`, `session-handoff.md`, `PROJECT-TOC.md`, `context-budget.md` | overwrites only with explicit approval |
| **/cpp-init** | C/C++ project, **after** `/anchor`, no clang cfg | `cpp-detect.sh`; instantiates `templates/cpp/*` | drops `.clang-format`, `.clang-tidy`, `scripts/sanitizer-build.sh`; tunes `init.sh` | asks before overwriting existing clang cfg; refuses on non-C/C++ |
| **/index-project** | `PROJECT-TOC.md` absent/stale, or before a broad search | `scripts/index-builder.mjs` (bootstraps from `PROJECT-TOC.md.tpl`) | rewrites `PROJECT-TOC.md` with a git-commit freshness anchor | errors if not a git repo |
| **/verify** `[--fix]` | before claiming a feature passes | **Task → `verification-runner`** (fresh context each cycle) | on PASS, updates `feature_list.json` status+evidence (via `feature-state-keeper`) | `--fix` bounded to **≤ 2** cycles; never self-grades; Default-FAIL (#8) |
| **/sanitize** | after a C/C++ change / before merge | `cpp-detect.sh`; `templates/cpp/sanitizer-build.sh.tpl` | runs ASan+UBSan (TSan separately) → `.harness-anchor/sanitize-*.log`; report mirrors `verification-runner` | refuses on non-C/C++ (via `cpp-detect.sh`); heavy ⇒ command, never a hook (#7) |
| **/status** | "where am I / what's the state?" | `toc-freshness.sh` | **nothing — read-only** snapshot (active feature, counts, git tree, TOC freshness, handoff head) | — |
| **/session-end** | at a stopping point | runs `init.sh` | overwrites `session-handoff.md`; prepends `progress.md`; updates `feature_list.json`; offers TOC refresh + commit | refuses `status=pass` without evidence (Default-FAIL); suggests `/anchor` if un-anchored |

---

## 4 · Model-pulled layer — skills & agents

Skills **auto-load by description** (the model "pulls" them). They don't call each other
directly; they (a) all reference **`docs-lookup`** as the canonical lookup procedure (invariant
#9), (b) *recommend* commands at the right moment, and (c) dispatch read-only **subagents** via
`Task` for fresh-context work.

```mermaid
flowchart LR
  classDef skill fill:#d9f5d9,stroke:#2e7d32,color:#000
  classDef agent fill:#ece3ff,stroke:#6a1b9a,color:#000
  classDef cmd fill:#d7ecff,stroke:#0277bd,color:#000
  classDef script fill:#f5f0d0,stroke:#9e8a00,color:#000

  DL["docs-lookup<br/>(lookup hub)"]:::skill
  META["using-harness-anchor (meta)"]:::skill

  PI["project-indexing"]:::skill
  FSK["feature-state-keeper"]:::skill
  IV["init-verification"]:::skill
  SCL["self-correction-loop"]:::skill
  AHG["anti-hallucination-gates"]:::skill
  CBD["context-budget-discipline"]:::skill
  CBS["cpp-build-systems"]:::skill
  CSA["cpp-static-analysis"]:::skill
  CF["cpp-formatting"]:::skill
  CS["cpp-sanitizers"]:::skill

  VR["verification-runner<br/>(read-only)"]:::agent
  BD["cpp-build-doctor<br/>(read-only)"]:::agent
  IC["index-curator<br/>(writes PROJECT-TOC.md)"]:::agent
  IB["index-builder.mjs"]:::script

  META -. "recommends all 7 commands" .-> CMDS["/anchor … /session-end"]:::cmd

  PI -.-> Ci["/index-project"]:::cmd
  FSK -.-> Cse["/session-end"]:::cmd
  FSK -.-> Cst["/status"]:::cmd
  IV -.-> Ca["/anchor"]:::cmd
  IV -.-> Cv["/verify"]:::cmd
  AHG -.-> Cv
  CBD -.-> Cv
  CBD -.-> Cse
  CF -.-> Ccpp["/cpp-init"]:::cmd
  CF -.-> Cse
  CSA -.-> Ccpp
  CS -.-> Csan["/sanitize"]:::cmd

  AHG -->|"Task"| VR
  SCL -->|"Task (re-verify)"| VR
  CBS -->|"Task"| BD
  CBD -->|"Task"| BD
  IC -->|"runs"| IB

  PI -. uses .-> DL
  FSK -. uses .-> DL
  IV -. uses .-> DL
  SCL -. uses .-> DL
  AHG -. uses .-> DL
  CBD -. uses .-> DL
  CBS -. uses .-> DL
  CSA -. uses .-> DL
  CF -. uses .-> DL
  CS -. uses .-> DL
  META -. uses .-> DL
```

### Skills

| Skill | Auto-triggers when | Recommends | Dispatches | Touches |
|---|---|---|---|---|
| **using-harness-anchor** (meta) | every session (injected by SessionStart) | **all 7 commands** | — | navigation: `AGENTS.md`, `feature_list.json`, `PROJECT-TOC.md`, `session-handoff.md` |
| **project-indexing** | locating files / understanding structure | `/index-project` | — | reads `PROJECT-TOC.md` before Glob |
| **feature-state-keeper** | start/advance/finish/block a feature | `/session-end`, `/status` | — | writes `feature_list.json`, `progress.md`, `session-handoff.md` |
| **init-verification** | start of work; after env change; something breaks | `/anchor`, `/verify` | — | runs `init.sh` |
| **self-correction-loop** | a hook/tool returns a warning, lint/type/build error, test failure | — | `verification-runner` | re-verify after fix |
| **anti-hallucination-gates** | before claiming "done/fixed/passing" | `/verify` | `verification-runner` | Default-FAIL evidence contract |
| **context-budget-discipline** | long sessions, subagents, large fetches | `/verify`, `/session-end` | `cpp-build-doctor` | `context-budget.md` |
| **docs-lookup** | unfamiliar tool/API/error/library | — (is itself the hub) | — | Context7 → WebSearch → calibrated-uncertainty |
| **cpp-build-systems** | C/C++ configure/build errors, `compile_commands.json` | — | `cpp-build-doctor` | build dir, `compile_commands.json` |
| **cpp-static-analysis** | reviewing C/C++ changes / hunting bugs | `/cpp-init` | — | needs `compile_commands.json`; `.clang-tidy` |
| **cpp-formatting** | C/C++ formatting | `/cpp-init`, `/session-end` | — | `.clang-format` (changed-lines only) |
| **cpp-sanitizers** | crashes / UB / races / memory errors | `/sanitize` | — | — |

### Agents (subagents — invoked via `Task`, single-level)

| Agent | Dispatched by | Tools | Effect |
|---|---|---|---|
| **verification-runner** | `/verify` (and re-used by `/sanitize`'s report shape, `anti-hallucination-gates`, `self-correction-loop`) | `Read, Bash, Grep, Glob` (read-only) | fresh-context build/test/lint → `### Build / Tests / Verdict / Recommendation` evidence report |
| **cpp-build-doctor** | `cpp-build-systems`, `context-budget-discipline` skills (when a C/C++ build fails) | `Read, Bash, Grep, Glob` (read-only) | diagnoses root cause from compiler output |
| **index-curator** | model-pulled by description (TOC needs rebuild: refactors/renames/`toc_stale`) | `Read, Bash, Grep, Glob, Write` | runs `index-builder.mjs`; **sole agent that writes `PROJECT-TOC.md`** |

---

## 5 · Scripts

**Runtime** scripts are called by hooks/commands/agents during a session. **Dev/CI** scripts
validate the plugin itself (run by `.github/workflows/validate.yml` and manually); they are *not*
part of the per-session call graph.

```mermaid
flowchart TB
  classDef script fill:#f5f0d0,stroke:#9e8a00,color:#000
  classDef hook fill:#fff0d0,stroke:#ef6c00,color:#000
  classDef cmd fill:#d7ecff,stroke:#0277bd,color:#000
  classDef agent fill:#ece3ff,stroke:#6a1b9a,color:#000
  classDef dev fill:#eceff1,stroke:#455a64,color:#000

  subgraph RT["runtime scripts"]
    cpd["cpp-detect.sh"]:::script
    tocf["toc-freshness.sh"]:::script
    ib["index-builder.mjs"]:::script
  end
  H1["session-start"]:::hook --> cpd
  H1 --> tocf
  C1["/anchor"]:::cmd --> cpd
  C2["/cpp-init"]:::cmd --> cpd
  C3["/sanitize"]:::cmd --> cpd
  C4["/status"]:::cmd --> tocf
  C5["/index-project"]:::cmd --> ib
  A1["index-curator"]:::agent --> ib

  subgraph DEV["dev / CI scripts (validate the plugin; run by CI + manually)"]
    va["validate-anchor.sh"]:::dev
    vm["validate-manifests.sh"]:::dev
    cat["check-allowed-tools.sh"]:::dev
    mc["measure-context.sh"]:::dev
    sch["schemas: plugin/marketplace .schema.json"]:::dev
  end
  va -->|"calls"| cat
  vm -->|"validates against"| sch
  CI["CI: validate.yml"]:::dev --> va
  CI --> vm
  CI --> cat
  CI --> mc
  CI --> cpd
  CI --> tests["tests/: hook-contracts · bench · e2e-cpp-fixture · posix-compat · skill-triggering"]:::dev
  mc -. "guards SessionStart 8000-char budget" .-> H1
```

| Script | Kind | Called by | Purpose |
|---|---|---|---|
| `cpp-detect.sh` | runtime | session-start hook, `/anchor`, `/cpp-init`, `/sanitize` | detect build system (CMake/Meson/Make/Bazel) — the C/C++ gate (invariant #5) |
| `toc-freshness.sh` | runtime | session-start hook, `/status` | compare `PROJECT-TOC.md` anchor commit vs HEAD |
| `index-builder.mjs` | runtime | `/index-project`, `index-curator` agent | scan `git ls-files`, build `PROJECT-TOC.md`; writes `.harness-anchor/last-error.log` on failure |
| `validate-anchor.sh` | dev/CI | CI, manual | plugin self-consistency (skills/commands/agents/templates/hooks); calls `check-allowed-tools.sh` |
| `validate-manifests.sh` | dev/CI | CI, manual | `plugin.json`/`marketplace.json` shape + version sync (uses `schemas/`) |
| `check-allowed-tools.sh` | dev/CI | `validate-anchor.sh`, CI | every `commands/*.md` declares a well-shaped `allowed-tools:` |
| `measure-context.sh` | dev/CI | CI, manual | SessionStart output vs the 8000-char budget (invariant #2) |

---

## 6 · Templates → output

Templates are inert `.tpl` files instantiated into per-project state by `/anchor` and `/cpp-init`.

| Template | Instantiated by | → Output (in the user's project) |
|---|---|---|
| `AGENTS.md.tpl` | `/anchor` | `AGENTS.md` (operating manual) |
| `feature_list.json.tpl` + `feature_list.schema.json` | `/anchor` | `feature_list.json` |
| `init.sh.tpl` | `/anchor` (tuned by `/cpp-init`) | `init.sh` |
| `progress.md.tpl` | `/anchor` | `progress.md` |
| `session-handoff.md.tpl` | `/anchor` | `session-handoff.md` |
| `PROJECT-TOC.md.tpl` | `/anchor`, `/index-project` (bootstrap) | `PROJECT-TOC.md` |
| `context-budget.md.tpl` | `/anchor` | `context-budget.md` |
| `cpp/.clang-format.tpl` | `/cpp-init` | `.clang-format` |
| `cpp/.clang-tidy.tpl` | `/cpp-init` | `.clang-tidy` |
| `cpp/sanitizer-build.sh.tpl` | `/cpp-init` (used by `/sanitize`) | `scripts/sanitizer-build.sh` |
| `cpp/cmake-init.sh.tpl`, `cpp/meson-init.sh.tpl` | `/cpp-init` | build-system-specific `init.sh` tuning |

---

## 7 · Shared state substrate — who writes, who reads

The state files are the **integration bus**: hooks read them to decide what to nudge; commands
and `feature-state-keeper` write them; agents read them for ground truth. All are git-tracked by
default **except `.harness-anchor/`** (runtime logs — the only gitignored path, invariant #4).

| State file | Written by | Read by |
|---|---|---|
| `feature_list.json` | `/anchor`, `/verify`, `/session-end`, `feature-state-keeper` | **all 4 hooks**, `/status`, `feature-state-keeper` |
| `progress.md` | `/anchor`, `/session-end`, `feature-state-keeper` | `stop` hook |
| `session-handoff.md` | `/anchor`, `/session-end` | `session-start` hook, `stop` hook, `/status` |
| `PROJECT-TOC.md` | `/index-project`, `index-curator` | `session-start` (via `toc-freshness.sh`), `project-indexing`, `/status` |
| `AGENTS.md` | `/anchor` | `using-harness-anchor` (navigation), subagents |
| `init.sh` | `/anchor` (tuned by `/cpp-init`) | `init-verification`, `/verify`, `/session-end` |
| `context-budget.md` | `/anchor` | `context-budget-discipline` |
| `.clang-format` / `.clang-tidy` | `/cpp-init` | `cpp-formatting`, `cpp-static-analysis`, `post-tool-use` (clang-tidy) |
| `compile_commands.json` | the project build (guided by `cpp-build-systems`) | `post-tool-use` (clang-tidy gate), `cpp-static-analysis` |
| `.harness-anchor/` (logs) | `index-builder.mjs`, `/sanitize` | humans / debugging (gitignored) |

---

## Design invariants the graph enforces

1. **Warn-only hooks** — every hook→command edge is *dashed* (a recommendation); no hook writes state or blocks.
2. **SessionStart ≤ 2000 tokens** — `measure-context.sh` guards the banner+meta-skill injection.
3. **Single-level subagents** — agents are leaf nodes (no agent→agent edges); each is dispatched by a command or skill, never from within another subagent.
4. **State is git-tracked except `.harness-anchor/`** — see §7.
5. **C/C++ gated by `cpp-detect.sh`** — every C/C++ command/skill routes through it.
6. *(Skill descriptions front-load trigger keywords — an authoring rule from CLAUDE.md, not something the call graph expresses; kept here only to preserve the canonical numbering.)*
7. **Hooks ≤ 5 s, fail-silent** — heavy work (`/sanitize`, `/verify --fix`) is a *command*, never a hook.
8. **Default-FAIL** — `/verify` → `verification-runner` (read-only, fresh context) is the only path to `status=pass`.
9. **docs-lookup is canonical** — every skill funnels lookups through it (§4).

*Generated for harness-anchor v0.3.2. Source of truth: `hooks/`, `commands/`, `skills/`, `agents/`, `scripts/`, `templates/`.*
