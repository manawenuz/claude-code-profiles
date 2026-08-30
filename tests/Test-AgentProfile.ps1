$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "agent-profile-test-$PID"
$homeDir = Join-Path $testRoot 'home'
$dataDir = Join-Path $testRoot 'data'
$guiSource = Join-Path $testRoot 'gui-source'

$agyHomeDir = Join-Path (Join-Path $homeDir '.gemini') 'antigravity-cli'
New-Item -ItemType Directory -Path $homeDir, $dataDir, $agyHomeDir, (Join-Path $guiSource 'User') -Force | Out-Null
$env:HOME = $homeDir
$env:USERPROFILE = $homeDir
$env:XDG_DATA_HOME = $dataDir
$env:AGENT_PROFILE_DATA_DIR = Join-Path $dataDir 'agent-profiles'
$env:AGENT_PROFILE_ANTIGRAVITY_GUI_DATA_DIR = $guiSource

# Keep inherited session state from affecting the assertions.
Remove-Item Env:AGENT_PROFILE_ANTIGRAVITY_ACTIVE -ErrorAction SilentlyContinue
Remove-Item Env:AGENT_PROFILE_CODEX_ACTIVE -ErrorAction SilentlyContinue

try {
    . (Join-Path $scriptRoot 'agent-profile-init.ps1')

    $script:assertionCount = 0
    function Assert-True([bool]$Condition, [string]$Message) {
        $script:assertionCount++
        if (-not $Condition) { throw "Assertion failed: $Message" }
    }

    Set-Content -LiteralPath (Join-Path $agyHomeDir 'token') -Value 'oauth-token'
    Set-Content -LiteralPath (Join-Path (Join-Path $guiSource 'User') 'settings.json') -Value 'gui-settings'
    agent-profile copy antigravity hafez | Out-Null
    $hafezDir = Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') 'hafez'
    Assert-True (Test-Path (Join-Path (Join-Path (Join-Path (Join-Path $hafezDir 'home') '.gemini') 'antigravity-cli') 'token')) 'copies live Antigravity CLI data'
    Assert-True (Test-Path (Join-Path (Join-Path (Join-Path $hafezDir 'gui-user-data') 'User') 'settings.json')) 'copies live GUI data'

    # Chromium's singleton entries name the host and pid of the instance that
    # owned the source directory. Copied into a profile they make Antigravity
    # focus the original window instead of opening the new profile, so a snapshot
    # must drop them -- and getting there must survive SingletonLock, whose
    # target deliberately does not exist.
    $singletonNames = @('SingletonLock', 'SingletonCookie', 'SingletonSocket')
    if (Test-APWindows) {
        # Symlinks need elevation or developer mode on Windows; plain files still
        # cover the prune itself.
        foreach ($name in $singletonNames) { Set-Content -LiteralPath (Join-Path $guiSource $name) -Value 'lock' }
    } else {
        # SingletonLock dangles by design, which is what used to abort the whole
        # copy: Copy-Item copies a link by value and cannot read a missing target.
        New-Item -ItemType SymbolicLink -Path (Join-Path $guiSource 'SingletonLock') -Value 'MacBook-Pro.local-77770' | Out-Null
        # The other two resolve, so the copy really does reproduce them into the
        # snapshot and the prune really does have to take them back out.
        Set-Content -LiteralPath (Join-Path $testRoot 'singleton-socket-target') -Value 'socket'
        Set-Content -LiteralPath (Join-Path $guiSource 'SingletonCookie') -Value '17350445988078770481'
        New-Item -ItemType SymbolicLink -Path (Join-Path $guiSource 'SingletonSocket') -Value (Join-Path $testRoot 'singleton-socket-target') | Out-Null
    }
    agent-profile copy antigravity locked | Out-Null
    $lockedGuiDir = Join-Path (Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') 'locked') 'gui-user-data'
    Assert-True (Test-Path (Join-Path (Join-Path $lockedGuiDir 'User') 'settings.json')) 'snapshots GUI data past a dangling singleton link'
    $leftoverLocks = @(Get-ChildItem -LiteralPath $lockedGuiDir -Force | Where-Object { $singletonNames -contains $_.Name })
    Assert-True ($leftoverLocks.Count -eq 0) 'prunes the Chromium singleton locks from a snapshot'

    agent-profile create antigravity work | Out-Null
    $workDir = Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') 'work'
    Set-Content -LiteralPath (Join-Path $workDir 'marker') -Value 'work'
    agent-profile default antigravity work | Out-Null
    agent-profile copy antigravity default copied | Out-Null
    $copiedDir = Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') 'copied'
    Assert-True ((Get-Content (Join-Path $copiedDir 'marker') -Raw).Trim() -eq 'work') 'copies from the persisted default'
    Assert-True ((agent-profile which antigravity copied) -like '*antigravity*copied') 'resolves a named profile'

    # The seam is Start-APProcess rather than Invoke-APGui: Invoke-APGui is the
    # function that builds the launch, so stubbing it would assert nothing about
    # the flag spelling or the child environment. Start-APProcess receives both
    # the finished argv and the environment handed to the GUI process.
    $guiStub = if (Test-APWindows) { Join-Path $testRoot 'antigravity-stub.cmd' } else { Join-Path $testRoot 'antigravity-stub' }
    if (Test-APWindows) {
        Set-Content -LiteralPath $guiStub -Value '@echo off'
    } else {
        Set-Content -LiteralPath $guiStub -Value "#!/bin/sh`nexit 0"
        & /bin/chmod '+x' $guiStub
    }
    $env:AGENT_PROFILE_ANTIGRAVITY_GUI_COMMAND = $guiStub

    $script:capturedGuiArgs = @()
    $script:capturedGuiEnvironment = @{}
    function Start-APProcess {
        param([string]$FilePath, [string[]]$Arguments, [hashtable]$Environment)
        $script:capturedGuiArgs = @($Arguments)
        $script:capturedGuiEnvironment = $Environment
        return 0
    }

    agent-profile use antigravity copied | Out-Null
    $copiedHome = Join-Path $copiedDir 'home'
    $copiedGuiData = Join-Path $copiedDir 'gui-user-data'

    antigravity | Out-Null
    # The "=" spelling is mandatory: the Antigravity app is a plain Electron app
    # whose Chromium parser silently ignores the space-separated form, which is
    # how the profile switch used to be a no-op.
    Assert-True ($script:capturedGuiArgs -contains "--user-data-dir=$copiedGuiData") 'GUI launch injects the equals-form --user-data-dir'
    # HOME is the knob that actually selects the Antigravity account: the app
    # resolves its real state from os.homedir()/.gemini.
    Assert-True ($script:capturedGuiEnvironment['HOME'] -eq $copiedHome) 'GUI launch puts the profile HOME in the child environment'
    if (Test-APWindows) {
        Assert-True ($script:capturedGuiEnvironment['USERPROFILE'] -eq $copiedHome) 'GUI launch also sets USERPROFILE on Windows'
    }
    # The launch also has to create both directories it points the GUI at.
    Assert-True (Test-Path -LiteralPath $copiedHome -PathType Container) 'GUI launch creates the profile home directory'
    Assert-True (Test-Path -LiteralPath $copiedGuiData -PathType Container) 'GUI launch creates the profile GUI data directory'

    agent-profile restart antigravity | Out-Null
    Assert-True ($script:capturedGuiArgs -contains '--new-window') 'restart requests a fresh GUI window'
    Assert-True ($script:capturedGuiArgs -contains "--user-data-dir=$copiedGuiData") 'restart keeps the equals-form --user-data-dir'
    Assert-True ($script:capturedGuiEnvironment['HOME'] -eq $copiedHome) 'restart puts the profile HOME in the child environment'

    # The agy CLI shares the same child-HOME mechanism, and both shell suites
    # assert it, so cover it here too now that the seam exposes the environment.
    $env:AGENT_PROFILE_AGY_COMMAND = $guiStub
    agy | Out-Null
    Assert-True ($script:capturedGuiEnvironment['HOME'] -eq $copiedHome) 'agy puts the profile HOME in the child environment'
    if (Test-APWindows) {
        Assert-True ($script:capturedGuiEnvironment['USERPROFILE'] -eq $copiedHome) 'agy also sets USERPROFILE on Windows'
    }

    # An explicit --user-data-dir wins: no flag is injected, but HOME still is.
    antigravity --user-data-dir /tmp/custom-gui | Out-Null
    $injected = @($script:capturedGuiArgs | Where-Object { $_ -like '--user-data-dir=*' })
    Assert-True ($injected.Count -eq 0) 'a user supplied --user-data-dir suppresses the injected one'
    Assert-True ($script:capturedGuiEnvironment['HOME'] -eq $copiedHome) 'a user supplied --user-data-dir still gets the profile HOME'

    $overwriteFailed = $false
    try { agent-profile copy antigravity work copied | Out-Null } catch { $overwriteFailed = $true }
    Assert-True $overwriteFailed 'refuses overwrite without --force'

    # With no profile selected the wrapper must stay transparent: no injected
    # flag and no child environment at all.
    Remove-Item Env:AGENT_PROFILE_ANTIGRAVITY_ACTIVE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') '.default') -Force
    antigravity --foo | Out-Null
    Assert-True ((@($script:capturedGuiArgs) -join ' ') -eq '--foo') 'an unselected provider passes argv through untouched'
    Assert-True ($script:capturedGuiEnvironment.Count -eq 0) 'an unselected provider sets no child environment'

    Write-Output "$script:assertionCount assertions passed, 0 failed"
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
