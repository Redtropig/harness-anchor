# .clang-tidy — harness-anchor baseline for C/C++ projects.
#
# Enables high-signal checks; excludes notoriously-noisy ones. Tune per project.
# Disabled-by-default: modernize-use-trailing-return-type, fuchsia-*, llvmlibc-*

Checks: >
  bugprone-*,
  cert-*,
  clang-analyzer-*,
  cppcoreguidelines-*,
  misc-*,
  performance-*,
  portability-*,
  readability-*,
  -bugprone-easily-swappable-parameters,
  -bugprone-narrowing-conversions,
  -cppcoreguidelines-avoid-magic-numbers,
  -cppcoreguidelines-non-private-member-variables-in-classes,
  -cppcoreguidelines-pro-bounds-array-to-pointer-decay,
  -cppcoreguidelines-pro-bounds-pointer-arithmetic,
  -cppcoreguidelines-pro-type-vararg,
  -misc-include-cleaner,
  -misc-non-private-member-variables-in-classes,
  -readability-identifier-length,
  -readability-magic-numbers,
  -readability-uppercase-literal-suffix

WarningsAsErrors: ''

HeaderFilterRegex: '^((?!/build/|/\.build/|/third_party/|/external/).)*$'

FormatStyle: file

CheckOptions:
  - key:   readability-identifier-naming.ClassCase
    value: CamelCase
  - key:   readability-identifier-naming.FunctionCase
    value: camelBack
  - key:   readability-identifier-naming.VariableCase
    value: lower_case
  - key:   readability-identifier-naming.MemberCase
    value: lower_case
  - key:   readability-identifier-naming.PrivateMemberSuffix
    value: '_'
  - key:   readability-identifier-naming.ConstantCase
    value: UPPER_CASE
  - key:   readability-function-cognitive-complexity.Threshold
    value: '25'
