: << 'CMDBLOCK'
@echo off
REM Cross-platform polyglot wrapper for harness-anchor hook scripts.
REM On Windows: cmd.exe runs the batch portion, which finds and calls bash.
REM On Unix: the shell interprets this as a script (: is a no-op in bash).
REM
REM Hook scripts use extensionless filenames (e.g. "session-start" not
REM "session-start.sh") so Claude Code's Windows auto-detection -- which
REM prepends "bash" to any command containing .sh -- doesn't interfere.
REM
REM bash discovery order: system Git, 32-bit Git, user-scope Git, then PATH --
REM skipping %SystemRoot%\System32\bash.exe (that is WSL bash: hooks launched
REM there see a Linux world where Windows project paths don't resolve).
REM
REM Usage: run-hook.cmd <script-name> [args...]

if "%~1"=="" (
    echo run-hook.cmd: missing script name >&2
    exit /b 1
)

set "HOOK_DIR=%~dp0"

if exist "%ProgramFiles%\Git\bin\bash.exe" (
    "%ProgramFiles%\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" (
    "%ProgramFiles(x86)%\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" (
    "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

REM PATH fallback (user-installed Git Bash, MSYS2, Cygwin) -- skip WSL's stub.
set "HA_BASH_EXE="
for /f "delims=" %%B in ('where bash.exe 2^>nul') do (
    if /I not "%%B"=="%SystemRoot%\System32\bash.exe" if not defined HA_BASH_EXE set "HA_BASH_EXE=%%B"
)
if defined HA_BASH_EXE (
    "%HA_BASH_EXE%" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

REM No usable bash found - exit silently rather than error
REM (plugin still works, just without hook context injection)
exit /b 0
CMDBLOCK

# Unix: run the named script directly with bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
