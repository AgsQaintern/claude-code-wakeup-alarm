# Install Claude Wakeup Alarm hooks into Claude Code settings.json
# Usage:
#   .\install.ps1
#   .\install.ps1 -Project
#   .\install.ps1 -ProjectPath "D:\my\repo"

[CmdletBinding()]
param(
    [switch]$Project,
    [string]$ProjectPath = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'lib\Common.ps1')

function Write-InstallMsg([string]$m) {
    if (-not $Quiet) { Write-Host $m }
}

$hookPs1 = Join-Path $root 'wakeup.ps1'
if (-not (Test-Path -LiteralPath $hookPs1)) {
    throw "wakeup.ps1 not found at $hookPs1"
}

# Claude hooks invoke a command string; use powershell -File with absolute path
$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$hookPs1`""

if ($Project -or $ProjectPath) {
    if (-not $ProjectPath) { $ProjectPath = $root }
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
    $settings = Join-Path $ProjectPath '.claude\settings.json'
    $scope = "project: $ProjectPath"
} else {
    $settings = Join-Path $env:USERPROFILE '.claude\settings.json'
    $scope = 'every Claude Code session (global)'
}

$settingsDir = Split-Path -Parent $settings
if (-not (Test-Path -LiteralPath $settingsDir)) {
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $settings)) {
    Set-Content -LiteralPath $settings -Value '{}' -Encoding UTF8
}

try {
    $raw = Get-Content -LiteralPath $settings -Raw -Encoding UTF8
    $null = $raw | ConvertFrom-Json
} catch {
    throw "Could not update Claude settings. Your existing settings were not changed. File is not valid JSON: $settings"
}

$backup = "$settings.bak.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
Copy-Item -LiteralPath $settings -Destination $backup -Force

try {
    $data = Get-Content -LiteralPath $settings -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $data.hooks) {
        $data | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force
    }

    function Get-HookGroups($arr) {
        $groups = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($arr)) {
            if ($null -eq $item) { continue }
            # unwrap accidental nested arrays from prior writes
            if ($item -is [System.Collections.IEnumerable] -and -not ($item -is [string]) -and -not ($item.PSObject.Properties['matcher'])) {
                foreach ($inner in @($item)) {
                    if ($null -ne $inner) { [void]$groups.Add($inner) }
                }
            } else {
                [void]$groups.Add($item)
            }
        }
        return $groups
    }

    function Strip-WakeupHooks($arr) {
        $out = New-Object System.Collections.Generic.List[object]
        foreach ($group in (Get-HookGroups $arr)) {
            $hooks = New-Object System.Collections.Generic.List[object]
            if ($group.PSObject.Properties['hooks'] -and $group.hooks) {
                foreach ($h in @($group.hooks)) {
                    $cmd = [string]$h.command
                    if ($cmd -notmatch 'wakeup\.ps1') { [void]$hooks.Add($h) }
                }
            }
            if ($hooks.Count -gt 0) {
                [void]$out.Add([pscustomobject]@{
                    matcher = $(if ($group.matcher) { [string]$group.matcher } else { '*' })
                    hooks   = @($hooks.ToArray())
                })
            }
        }
        return @($out.ToArray())
    }

    $entry = [pscustomobject]@{
        matcher = '*'
        hooks   = @(
            [pscustomobject]@{
                type    = 'command'
                command = $command
                shell   = 'powershell'
                timeout = 5
            }
        )
    }

    $keptNotify = @(Strip-WakeupHooks $data.hooks.Notification)
    $keptStop = @(Strip-WakeupHooks $data.hooks.Stop)
    $notification = @($keptNotify + @($entry))
    $stop = @($keptStop + @($entry))

    $hooksObj = [ordered]@{}
    # preserve other hook event keys
    foreach ($p in $data.hooks.PSObject.Properties) {
        if ($p.Name -eq 'Notification' -or $p.Name -eq 'Stop') { continue }
        $hooksObj[$p.Name] = $p.Value
    }
    $hooksObj['Notification'] = $notification
    $hooksObj['Stop'] = $stop

    $data.hooks = [pscustomobject]$hooksObj

    $tmp = "$settings.tmp.$PID"
    $json = ($data | ConvertTo-Json -Depth 20)
    [System.IO.File]::WriteAllText($tmp, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    # validate
    $null = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
    Move-Item -LiteralPath $tmp -Destination $settings -Force
}
catch {
    Write-Error "Could not update Claude settings. Your existing settings were not changed. See logs for technical details."
    Write-WakeupEngineLog ("install failed: {0}" -f $_.Exception.Message)
    if (Test-Path -LiteralPath $backup) {
        # leave backup; settings untouched if move failed mid-way - restore if tmp replaced badly
    }
    throw
}

Write-InstallMsg "installed -> $settings  (active for: $scope)"
Write-InstallMsg "backup    -> $backup"
Write-InstallMsg ''
Write-InstallMsg 'Hooks load when a session starts, so restart Claude Code to arm it.'
Write-InstallMsg ("Log: {0}" -f (Get-WakeupLogPath))

# Update UI scope hint in config when installing
try {
    $cfg = Read-WakeupConfig
    if ($Project -or $ProjectPath) {
        $cfg.ui.scope = 'project'
        $cfg.ui.projectPath = $ProjectPath
    } else {
        $cfg.ui.scope = 'global'
    }
    Write-WakeupConfig -Config $cfg
} catch {}
