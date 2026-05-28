# compile_commands.json — Deep Dive

This file is a JSON array of "compile command" objects, one per source file. It tells tools (clang-tidy, clangd, IWYU) exactly how each file is compiled — flags, macros, includes, standard.

## Anatomy of one entry

```json
{
  "directory": "/abs/path/.build",
  "command": "/usr/bin/c++ -DDEBUG=1 -Iinclude -std=gnu++20 -o CMakeFiles/foo.dir/src/foo.cpp.o -c /abs/path/src/foo.cpp",
  "file": "/abs/path/src/foo.cpp"
}
```

Or with `arguments` (array form):

```json
{
  "directory": "...",
  "arguments": ["/usr/bin/c++", "-DDEBUG=1", "-Iinclude", "-std=gnu++20", "-c", "src/foo.cpp"],
  "file": "..."
}
```

Tools accept either form.

## How tools find it

By default tools look upward from the file's directory for `compile_commands.json`. So a symlink from project root to `.build/compile_commands.json` is enough.

## When it's stale

If you add a source file but don't re-configure:
- New file is not in compile_commands.json
- clang-tidy on that file falls back to defaults — misses your includes/macros
- Errors look mysterious ("no member named X")

Fix: re-run the configure step (`cmake -S . -B .build` or `meson setup --reconfigure`).

## When the build dir is missing/clean

The file points to `.build/CMakeFiles/...` for object files. If you `rm -rf .build` but keep compile_commands.json, the directory references are stale but the *compile flags* are still valid for static analysis tools. So static analysis often works on a "cleaned" build dir.

## Header-only files

Headers don't appear in compile_commands.json (they're not compiled directly). Tools handle this by:

- clangd: searches for any source that includes the header, uses *that* source's flags
- clang-tidy: same, with `-header-filter` to scope what gets analyzed

This means: don't worry about headers being "missing" from compile_commands.json.

## Cross-build / multi-config

If you have `.build/debug` AND `.build/release`, the static analysis tools will care about flags. Conventionally use the Debug build's compile_commands.json for analysis (more checks enabled).

## Symlinks vs. files

- Symlink to active build dir's compile_commands.json: flexible, works for one config at a time
- Copying: discouraged; gets stale

Some projects commit a generated compile_commands.json; this is usually a mistake — it goes stale and bloats the repo. `.gitignore` it.

## Verification

```bash
# Show file count covered
jq 'length' compile_commands.json

# Show one entry
jq '.[0]' compile_commands.json

# List files
jq -r '.[].file' compile_commands.json | head
```
