@echo off
setlocal enabledelayedexpansion

:: --- Platform-aware data directory ---
:: Uses %LOCALAPPDATA%\claude-profiles on Windows
set "DATA_DIR=%LOCALAPPDATA%\claude-profiles"
set "DEFAULT_FILE=%DATA_DIR%\.default"

:: --- Version tracking ---
set "_CP_INSTALL_DIR=%LOCALAPPDATA%\claude-profile"
set "_CP_VERSION_FILE=%_CP_INSTALL_DIR%\VERSION"
set "_CP_UPDATE_CACHE=%_CP_INSTALL_DIR%\.update-check"
set "_CP_REPO_API=https://api.github.com/repos/pegasusheavy/claude-code-profiles"
if defined CLAUDE_PROFILE_UPDATE_API_BASE set "_CP_REPO_API=%CLAUDE_PROFILE_UPDATE_API_BASE%"
set "_CP_UPDATE_INTERVAL=86400"
if defined CLAUDE_PROFILE_UPDATE_CHECK_INTERVAL set "_CP_UPDATE_INTERVAL=%CLAUDE_PROFILE_UPDATE_CHECK_INTERVAL%"
echo %_CP_UPDATE_INTERVAL%| findstr /R "^[0-9][0-9]*$" >nul 2>&1 || set "_CP_UPDATE_INTERVAL=86400"

:: --- Dispatcher ---
call :cp_update_check
:: No arguments: launch with default profile
if "%~1"=="" goto :cmd_launch_default

:: Command dispatch
if "%~1"=="create"  goto :dispatch_create
if "%~1"=="list"    goto :dispatch_list
if "%~1"=="ls"      goto :dispatch_list
if "%~1"=="default" goto :dispatch_default
if "%~1"=="which"   goto :dispatch_which
if "%~1"=="use"     goto :dispatch_use
if "%~1"=="delete"  goto :dispatch_delete
if "%~1"=="help"    goto :usage
if "%~1"=="-h"      goto :usage
if "%~1"=="--help"  goto :usage
if "%~1"=="version" goto :dispatch_version

:: Flags without a subcommand are not supported
set "_first=%~1"
if "!_first:~0,1!"=="-" (
    echo claude-profile: unknown command '%~1'. Run 'claude-profile help' for usage. >&2
    exit /b 1
)

:: Unknown command
echo claude-profile: unknown command '%~1'. Run 'claude-profile help' for usage. >&2
exit /b 1

:: --- Dispatch helpers (shift then jump) ---

:dispatch_create
shift
goto :cmd_create

:dispatch_list
shift
goto :cmd_list

:dispatch_default
shift
goto :cmd_default

:dispatch_which
shift
goto :cmd_which

:dispatch_use
shift
goto :cmd_use

:dispatch_delete
shift
goto :cmd_delete

:dispatch_version
shift
goto :cmd_version

:get_epoch
:: cmd has no native epoch-time support; PowerShell ships with every
:: supported Windows version, so shell out to it rather than reinventing
:: date arithmetic in batch.
set "_cp_epoch="
for /f %%e in ('powershell -NoProfile -Command "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()" 2^>nul') do set "_cp_epoch=%%e"
if not defined _cp_epoch set "_cp_epoch=0"
goto :eof

:: extract_tag_version <raw findstr line containing "tag_name":"..."> ->
:: sets _cp_tag_version (without leading v) on success, leaves it undefined
:: on failure.
:extract_tag_version
set "_cp_tag_version="
set "_etv_line=%~1"
for /f "tokens=2 delims=:" %%v in ("!_etv_line!") do set "_etv_raw=%%v"
set "_etv_raw=!_etv_raw:"=!"
set "_etv_raw=!_etv_raw: =!"
set "_etv_raw=!_etv_raw:,=!"
if "!_etv_raw:~0,1!"=="v" set "_etv_raw=!_etv_raw:~1!"
echo !_etv_raw!| findstr /R "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul 2>&1
if not errorlevel 1 set "_cp_tag_version=!_etv_raw!"
goto :eof

:: version_lt <a> <b> -> errorlevel 0 if a<b, 1 otherwise.
:: "unknown" is always < any real version, and equal to itself.
:version_lt
set "_vlt_a=%~1"
set "_vlt_b=%~2"
if "!_vlt_a!"=="unknown" (
    if "!_vlt_b!"=="unknown" (exit /b 1) else (exit /b 0)
)
if "!_vlt_b!"=="unknown" exit /b 1
for /f "tokens=1-3 delims=." %%x in ("!_vlt_a!") do (set "_vlt_a1=%%x" & set "_vlt_a2=%%y" & set "_vlt_a3=%%z")
for /f "tokens=1-3 delims=." %%x in ("!_vlt_b!") do (set "_vlt_b1=%%x" & set "_vlt_b2=%%y" & set "_vlt_b3=%%z")
if !_vlt_a1! lss !_vlt_b1! exit /b 0
if !_vlt_a1! gtr !_vlt_b1! exit /b 1
if !_vlt_a2! lss !_vlt_b2! exit /b 0
if !_vlt_a2! gtr !_vlt_b2! exit /b 1
if !_vlt_a3! lss !_vlt_b3! exit /b 0
exit /b 1

:: write_update_cache <epoch> <version> <notified> — atomic via temp+rename
:write_update_cache
if not exist "%_CP_INSTALL_DIR%" mkdir "%_CP_INSTALL_DIR%" >nul 2>&1
set "_wuc_tmp=%_CP_UPDATE_CACHE%.tmp.%RANDOM%"
(
    echo %~1
    echo %~2
    echo %~3
)>"!_wuc_tmp!" 2>nul
if exist "!_wuc_tmp!" (
    move /y "!_wuc_tmp!" "%_CP_UPDATE_CACHE%" >nul 2>&1 || del /f /q "!_wuc_tmp!" >nul 2>&1
)
goto :eof

:cp_update_check
if defined CLAUDE_PROFILE_NO_UPDATE_CHECK goto :eof
where curl >nul 2>&1
if errorlevel 1 goto :eof

set "_cpu_ts=0"
set "_cpu_ver=unknown"
set "_cpu_notified=0"
if exist "%_CP_UPDATE_CACHE%" (
    set "_cpu_line=0"
    for /f "usebackq delims=" %%L in ("%_CP_UPDATE_CACHE%") do (
        set /a _cpu_line+=1
        if "!_cpu_line!"=="1" set "_cpu_ts=%%L"
        if "!_cpu_line!"=="2" set "_cpu_ver=%%L"
        if "!_cpu_line!"=="3" set "_cpu_notified=%%L"
    )
)

call :get_epoch
set /a _cpu_elapsed=_cp_epoch-_cpu_ts

if !_cpu_elapsed! geq !_CP_UPDATE_INTERVAL! (
    set "_cpu_resp_file=%TEMP%\cp-release-%RANDOM%.json"
    curl -fsSL --connect-timeout 3 --max-time 3 -o "!_cpu_resp_file!" "%_CP_REPO_API%/releases/latest" >nul 2>&1
    set "_cpu_new_ver=!_cpu_ver!"
    if exist "!_cpu_resp_file!" (
        set "_cpu_tagline="
        for /f "usebackq delims=" %%T in (`findstr /R "\"tag_name\"" "!_cpu_resp_file!"`) do set "_cpu_tagline=%%T"
        del /f /q "!_cpu_resp_file!" >nul 2>&1
        if defined _cpu_tagline (
            call :extract_tag_version "!_cpu_tagline!"
            if defined _cp_tag_version set "_cpu_new_ver=!_cp_tag_version!"
        )
    )
    if not "!_cpu_new_ver!"=="!_cpu_ver!" (
        call :write_update_cache "!_cp_epoch!" "!_cpu_new_ver!" "0"
        set "_cpu_ver=!_cpu_new_ver!"
        set "_cpu_notified=0"
    ) else (
        call :write_update_cache "!_cp_epoch!" "!_cpu_ver!" "!_cpu_notified!"
    )
)

if "!_cpu_notified!"=="0" if not "!_cpu_ver!"=="unknown" (
    set "_cpu_installed=unknown"
    if exist "%_CP_VERSION_FILE%" set /p _cpu_installed=<"%_CP_VERSION_FILE%"
    if "!_cpu_installed!"=="" set "_cpu_installed=unknown"
    if not "!_cpu_installed!"=="unknown" (
        echo !_cpu_installed!| findstr /R "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul 2>&1
        if errorlevel 1 set "_cpu_installed=unknown"
    )
    call :version_lt "!_cpu_installed!" "!_cpu_ver!"
    if not errorlevel 1 (
        echo A new claude-profile version is available ^(v!_cpu_installed! -^> v!_cpu_ver!^). Run 'claude-profile update' to upgrade. >&2
        call :write_update_cache "!_cp_epoch!" "!_cpu_ver!" "1"
    )
)
goto :eof

:: --- Usage ---

:usage
echo Usage: claude-profile [command] [args...]
echo.
echo Commands:
echo     (no command)            Activate the default profile
echo     use ^<name^>              Activate the named profile
echo     create ^<name^>           Create a new profile
echo     list, ls                List all profiles
echo     default [name]          Get or set the default profile
echo     delete ^<name^>           Delete a profile
echo     which [name]            Show the resolved config directory path
echo     version                 Show the installed version
echo     help, -h, --help        Show this help message
echo.
echo Use 'call claude-profile use ^<name^>' to set CLAUDE_CONFIG_DIR in the
echo current cmd session, then run 'claude' separately.
echo.
echo Examples:
echo     claude-profile create work
echo     claude-profile default work
echo     call claude-profile use work     # activates "work" profile
echo     claude                           # runs with "work" profile
exit /b 0

:: --- Validate name ---
:: Expects profile name in %_vn_name%
:: Returns errorlevel 1 on failure

:validate_name

:: Check empty
if "%_vn_name%"=="" (
    echo claude-profile: profile name must not be empty >&2
    exit /b 1
)

:: Check starts with dot
if "!_vn_name:~0,1!"=="." (
    echo claude-profile: invalid profile name '%_vn_name%': must not contain '/' or start with '.' >&2
    exit /b 1
)

:: Check for path traversal and slashes (/  \  ..)
:: We use findstr with regex mode for reliable matching
echo !_vn_name! | findstr /R "[/\\]" >nul 2>&1 && (
    echo claude-profile: invalid profile name '%_vn_name%': must not contain '/' or start with '.' >&2
    exit /b 1
)
echo !_vn_name! | findstr /C:".." >nul 2>&1 && (
    echo claude-profile: invalid profile name '%_vn_name%': must not contain '/' or start with '.' >&2
    exit /b 1
)

:: Check only valid characters (letters, digits, hyphens, underscores)
echo !_vn_name!| findstr /R "^[a-zA-Z0-9_-][a-zA-Z0-9_-]*$" >nul 2>&1 || (
    echo claude-profile: invalid profile name '%_vn_name%': use only letters, digits, hyphens, underscores >&2
    exit /b 1
)

goto :eof

:: --- Commands ---

:cmd_create
if "%~1"=="" (
    echo claude-profile: usage: claude-profile create ^<name^> >&2
    exit /b 1
)
set "_vn_name=%~1"
call :validate_name
if errorlevel 1 exit /b 1

set "_cc_dir=%DATA_DIR%\%~1"
if exist "%_cc_dir%\" (
    echo claude-profile: profile '%~1' already exists >&2
    exit /b 1
)
mkdir "%_cc_dir%"
echo Created profile: %~1
echo Config directory: %_cc_dir%
exit /b 0

:cmd_list
if not exist "%DATA_DIR%\" (
    echo No profiles found. Create one with: claude-profile create ^<name^>
    exit /b 0
)

set "_cl_default="
if exist "%DEFAULT_FILE%" (
    set /p _cl_default=<"%DEFAULT_FILE%"
)

set "_cl_found=0"
for /d %%d in ("%DATA_DIR%\*") do (
    set "_cl_found=1"
    set "_cl_name=%%~nxd"
    if "!_cl_name!"=="!_cl_default!" (
        echo * !_cl_name! (default^)
    ) else (
        echo   !_cl_name!
    )
)

if "!_cl_found!"=="0" (
    echo No profiles found. Create one with: claude-profile create ^<name^>
)
exit /b 0

:cmd_default
if "%~1"=="" (
    if exist "%DEFAULT_FILE%" (
        type "%DEFAULT_FILE%"
        echo.
        exit /b 0
    ) else (
        echo claude-profile: no default profile set. Set one with: claude-profile default ^<name^> >&2
        exit /b 1
    )
)

set "_vn_name=%~1"
call :validate_name
if errorlevel 1 exit /b 1

set "_cd_dir=%DATA_DIR%\%~1"
if not exist "%_cd_dir%\" (
    echo claude-profile: profile '%~1' does not exist. Create it with: claude-profile create %~1 >&2
    exit /b 1
)
if not exist "%DATA_DIR%\" mkdir "%DATA_DIR%"
:: Write profile name without trailing newline (cmd echo always adds one, but set /p reads the first line)
>"%DEFAULT_FILE%" (echo|set /p="%~1")
echo Default profile set to: %~1
exit /b 0

:cmd_version
set "_cv_installed=unknown"
if exist "%_CP_VERSION_FILE%" set /p _cv_installed=<"%_CP_VERSION_FILE%"
if "!_cv_installed!"=="" set "_cv_installed=unknown"
echo !_cv_installed!
exit /b 0

:cmd_which
:: Resolve profile dir for optional name argument
set "_rp_name=%~1"
if "!_rp_name!"=="" (
    if not exist "%DEFAULT_FILE%" (
        echo claude-profile: no default profile set. Use: claude-profile default ^<name^> >&2
        exit /b 1
    )
    set /p _rp_name=<"%DEFAULT_FILE%"
    if "!_rp_name!"=="" (
        echo claude-profile: default profile file is empty. Set one with: claude-profile default ^<name^> >&2
        exit /b 1
    )
)
set "_rp_dir=%DATA_DIR%\!_rp_name!"
if not exist "!_rp_dir!\" (
    echo claude-profile: profile '!_rp_name!' does not exist. Create it with: claude-profile create !_rp_name! >&2
    exit /b 1
)
echo !_rp_dir!
exit /b 0

:cmd_use
if "%~1"=="" (
    echo claude-profile: usage: claude-profile use ^<name^> >&2
    exit /b 1
)
if not "%~2"=="" (
    echo claude-profile: 'use' takes exactly one argument (profile name) >&2
    exit /b 1
)

:: Resolve profile dir
set "_rp_name=%~1"
set "_rp_dir=%DATA_DIR%\!_rp_name!"
if not exist "!_rp_dir!\" (
    echo claude-profile: profile '!_rp_name!' does not exist. Create it with: claude-profile create !_rp_name! >&2
    exit /b 1
)

:: Set CLAUDE_CONFIG_DIR for the calling session (requires 'call' prefix)
endlocal & set "CLAUDE_CONFIG_DIR=%_rp_dir%" & echo Switched to profile: %_rp_name%
exit /b 0

:cmd_delete
if "%~1"=="" (
    echo claude-profile: usage: claude-profile delete ^<name^> >&2
    exit /b 1
)
set "_cdel_name=%~1"
set "_vn_name=!_cdel_name!"
call :validate_name
if errorlevel 1 exit /b 1

set "_cdel_dir=%DATA_DIR%\!_cdel_name!"
if not exist "!_cdel_dir!\" (
    echo claude-profile: profile '!_cdel_name!' does not exist >&2
    exit /b 1
)

set "_cdel_prompt=Delete profile "!_cdel_name!" and all its data? [y/N] "
set /p _cdel_confirm=!_cdel_prompt!
if /i "!_cdel_confirm!"=="y" goto :do_delete
if /i "!_cdel_confirm!"=="yes" goto :do_delete
echo Cancelled.
exit /b 0

:do_delete
rmdir /s /q "!_cdel_dir!"
echo Deleted profile: !_cdel_name!

if exist "%DEFAULT_FILE%" (
    set /p _cdel_current=<"%DEFAULT_FILE%"
    if "!_cdel_current!"=="!_cdel_name!" (
        del /f "%DEFAULT_FILE%" >nul 2>&1
        echo Cleared default profile (was "!_cdel_name!"^)
    )
)
exit /b 0

:cmd_launch_default
:: Resolve default profile
if not exist "%DEFAULT_FILE%" (
    echo claude-profile: no default profile set. Use: claude-profile default ^<name^> >&2
    exit /b 1
)
set /p _rp_name=<"%DEFAULT_FILE%"
if "!_rp_name!"=="" (
    echo claude-profile: default profile file is empty. Set one with: claude-profile default ^<name^> >&2
    exit /b 1
)
set "_rp_dir=%DATA_DIR%\!_rp_name!"
if not exist "!_rp_dir!\" (
    echo claude-profile: profile '!_rp_name!' does not exist. Create it with: claude-profile create !_rp_name! >&2
    exit /b 1
)

:: Set CLAUDE_CONFIG_DIR for the calling session (requires 'call' prefix)
endlocal & set "CLAUDE_CONFIG_DIR=%_rp_dir%" & echo Switched to profile: %_rp_name% (default)
exit /b 0
