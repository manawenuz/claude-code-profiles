@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "GUI_EXE=%AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND%"
if not defined GUI_EXE for /f "delims=" %%E in ('where antigravity-ide.exe 2^>nul') do if not defined GUI_EXE set "GUI_EXE=%%E"
if not defined GUI_EXE for /f "delims=" %%E in ('where antigravity.exe 2^>nul') do if not defined GUI_EXE set "GUI_EXE=%%E"
if not defined GUI_EXE (
    echo agent-profile: could not find antigravity GUI; set AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND >&2
    exit /b 127
)
set "GUI_PROFILE="
for /f "delims=" %%P in ('call "%~dp0agent-profile.cmd" internal-path antigravity 2^>nul') do if not defined GUI_PROFILE set "GUI_PROFILE=%%P"
set "HAS_DATA_ARG=0"
for %%A in (%*) do (
    set "GUI_ARG=%%~A"
    if /i "!GUI_ARG!"=="--user-data-dir" set "HAS_DATA_ARG=1"
    if /i "!GUI_ARG:~0,16!"=="--user-data-dir=" set "HAS_DATA_ARG=1"
)
if not defined GUI_PROFILE (
    endlocal & "%GUI_EXE%" %*
    exit /b %ERRORLEVEL%
)
if "%HAS_DATA_ARG%"=="1" (
    endlocal & "%GUI_EXE%" %*
) else (
    set "GUI_DATA=%GUI_PROFILE%\gui-user-data"
    endlocal & "%GUI_EXE%" --user-data-dir "%GUI_DATA%" %*
)
exit /b %ERRORLEVEL%
