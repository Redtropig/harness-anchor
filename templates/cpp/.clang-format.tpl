# .clang-format — harness-anchor baseline for C/C++ projects.
# Based on LLVM with widely-accepted tweaks. Pin clang-format major version
# in CI to avoid drift between dev machines.
BasedOnStyle: LLVM
Language: Cpp
Standard: c++20

IndentWidth: 4
TabWidth: 4
UseTab: Never
ColumnLimit: 100

AllowShortFunctionsOnASingleLine: Empty
AllowShortIfStatementsOnASingleLine: Never
AllowShortLoopsOnASingleLine: false
AllowShortBlocksOnASingleLine: Empty

AlignAfterOpenBracket: BlockIndent
AlignConsecutiveAssignments: false
AlignConsecutiveDeclarations: false
AlignTrailingComments: true

BinPackArguments: false
BinPackParameters: false

BreakBeforeBraces: Attach
BreakConstructorInitializers: BeforeColon

PointerAlignment: Left
DerivePointerAlignment: false

SortIncludes: CaseInsensitive
IncludeBlocks: Regroup
IncludeCategories:
  - Regex:           '^"'              # local headers first
    Priority:        1
  - Regex:           '^<.*\.(h|hpp)>$'  # external libs
    Priority:        2
  - Regex:           '^<[^/]+>$'       # std headers
    Priority:        3

SpacesBeforeTrailingComments: 2
SpaceAfterCStyleCast: false
SpaceBeforeAssignmentOperators: true
SpaceBeforeParens: ControlStatements

# Penalize wrapping; readable lines win
PenaltyExcessCharacter: 1000000
