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

try {
    . (Join-Path $scriptRoot 'agent-profile-init.ps1')

    function Assert-True([bool]$Condition, [string]$Message) {
        if (-not $Condition) { throw "Assertion failed: $Message" }
    }

    Set-Content -LiteralPath (Join-Path $agyHomeDir 'token') -Value 'oauth-token'
    Set-Content -LiteralPath (Join-Path (Join-Path $guiSource 'User') 'settings.json') -Value 'gui-settings'
    agent-profile copy antigravity hafez | Out-Null
    $hafezDir = Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') 'hafez'
    Assert-True (Test-Path (Join-Path (Join-Path (Join-Path (Join-Path $hafezDir 'home') '.gemini') 'antigravity-cli') 'token')) 'copies live Antigravity CLI data'
    Assert-True (Test-Path (Join-Path (Join-Path (Join-Path $hafezDir 'gui-user-data') 'User') 'settings.json')) 'copies live GUI data'

    agent-profile create antigravity work | Out-Null
    $workDir = Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') 'work'
    Set-Content -LiteralPath (Join-Path $workDir 'marker') -Value 'work'
    agent-profile default antigravity work | Out-Null
    agent-profile copy antigravity default copied | Out-Null
    $copiedDir = Join-Path (Join-Path $env:AGENT_PROFILE_DATA_DIR 'antigravity') 'copied'
    Assert-True ((Get-Content (Join-Path $copiedDir 'marker') -Raw).Trim() -eq 'work') 'copies from the persisted default'
    Assert-True ((agent-profile which antigravity copied) -like '*antigravity*copied') 'resolves a named profile'

    $script:capturedGuiArgs = @()
    function Invoke-APGui {
        param([string[]]$Arguments)
        $script:capturedGuiArgs = @($Arguments)
        return 0
    }
    agent-profile restart antigravity | Out-Null
    Assert-True ($script:capturedGuiArgs -contains '--new-window') 'restart requests a fresh GUI window'

    $overwriteFailed = $false
    try { agent-profile copy antigravity work copied | Out-Null } catch { $overwriteFailed = $true }
    Assert-True $overwriteFailed 'refuses overwrite without --force'
    Write-Output '6 assertions passed'
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
