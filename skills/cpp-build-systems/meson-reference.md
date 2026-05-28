# Meson Quick Reference

## Minimal modern project

```meson
project('my_project', 'cpp',
    version: '0.1.0',
    default_options: ['cpp_std=c++20', 'warning_level=3'])

executable('my_app', 'src/main.cpp')
```

## Library + executable

```meson
my_lib = static_library('my_lib', 'src/lib.cpp',
    include_directories: include_directories('include'))

executable('my_app', 'src/main.cpp',
    link_with: my_lib)
```

## External dep

```meson
fmt_dep = dependency('fmt')
executable('my_app', 'src/main.cpp', dependencies: fmt_dep)
```

## Tests

```meson
test_exe = executable('my_tests', 'tests/test_main.cpp',
    dependencies: dependency('gtest_main'),
    link_with: my_lib)
test('all', test_exe)
```

Run: `meson test -C builddir`

## Sanitizer build

```bash
meson setup builddir-asan -Db_sanitize=address,undefined
meson compile -C builddir-asan
```

## Compile commands

Meson emits `compile_commands.json` automatically into builddir. Symlink it:

```bash
ln -sf builddir/compile_commands.json .
```

## When to prefer Meson over CMake

- Faster configure step
- Cleaner syntax (declarative, not scripty)
- Built-in cross-compilation
- Built-in subprojects without FetchContent gymnastics

When to prefer CMake: ecosystem (more libraries provide CMake configs than Meson).
