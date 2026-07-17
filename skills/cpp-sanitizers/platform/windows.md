# cpp-sanitizers — Windows substitute tools

Operational companion to SKILL.md's availability matrix (the decision facts —
what is unavailable, what works natively, the never-CLEAN rule — live there).
This file is the substitute-tool playbook; preference order matters, and a
refusal should always name a substitute.

| Unavailable on Windows | Use instead (preference order) |
|---|---|
| TSan (data races) | ① Run the TSan arm under **WSL2** or Linux CI (closest fidelity); ② **Intel Inspector** (oneAPI) for native data-race/deadlock detection |
| LSan (leaks) | ① **MSVC CRT debug heap** (`_CrtSetDbgFlag(_CRTDBG_LEAK_CHECK_DF)` / `_CrtDumpMemoryLeaks` — ships with MSVC); ② **Dr. Memory**; ③ **UMDH** (Windows SDK); ④ WSL2/Linux-CI LSan |
| UBSan under MSVC `cl.exe` | ① **clang-on-Windows** `-fsanitize=undefined` (partial set; MinGW or clang-cl); ② **MSVC `/RTC1`** runtime checks (narrower: uninit locals, stack corruption) |
| Valgrind | ① **Dr. Memory**; ② **Application Verifier + PageHeap** (`gflags /p`) for heap/handle misuse |
