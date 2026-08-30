@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "AGY_EXE="
for /f "delims=" %%E in ('where agy.exe 2^>nul') do if not defined AGY_EXE set "AGY_EXE=%%E"
if not defined AGY_EXE set "AGY_EXE=agy.exe"
set "AGY_PROFILE="
for /f "delims=" %%P in ('call "%~dp0agent-profile.cmd" internal-path antigravity 2^>nul') do if not defined AGY_PROFILE set "AGY_PROFILE=%%P"
if not defined AGY_PROFILE (
    endlocal & "%AGY_EXE%" %*
    exit /b %ERRORLEVEL%
)
set "AGY_HOME=%AGY_PROFILE%\home"
endlocal & set "HOME=%AGY_HOME%" & set "USERPROFILE=%AGY_HOME%" & "%AGY_EXE%" %*
exit /b %ERRORLEVEL%
