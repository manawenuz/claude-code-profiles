@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "CODEX_EXE="
for /f "delims=" %%E in ('where codex.exe 2^>nul') do if not defined CODEX_EXE set "CODEX_EXE=%%E"
if not defined CODEX_EXE set "CODEX_EXE=codex.exe"
set "CODEX_PROFILE="
for /f "delims=" %%P in ('call "%~dp0agent-profile.cmd" internal-path codex 2^>nul') do if not defined CODEX_PROFILE set "CODEX_PROFILE=%%P"
if not defined CODEX_PROFILE (
    endlocal & "%CODEX_EXE%" %*
    exit /b %ERRORLEVEL%
)
endlocal & set "CODEX_HOME=%CODEX_PROFILE%" & "%CODEX_EXE%" %*
exit /b %ERRORLEVEL%
