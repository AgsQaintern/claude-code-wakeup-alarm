# Remove Claude Wakeup Alarm hooks. Leaves every other setting untouched.
# Usage:
#   .\uninstall.ps1
#   .\uninstall.ps1 -Project
#   .\uninstall.ps1 -ProjectPath "D:\my\repo"

[CmdletBinding()]
param(
    [switch]$Project,
    [string]$ProjectPath = '',
    [switch]$Quiet,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'lib\Common.ps1')

function Write-UninstallMsg([string]$m) {
    if (-not $Quiet) { Write-Host $m }
}

if ($Project -or $ProjectPath) {
    if (-not $ProjectPath) { $ProjectPath = $root }
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
    $settings = Join-Path $ProjectPath '.claude\settings.json'
} else {
    $settings = Join-Path $env:USERPROFILE '.claude\settings.json'
}

if (-not (Test-Path -LiteralPath $settings)) {
    Write-UninstallMsg "nothing to do: $settings does not exist"
    exit 0
}

$backup = "$settings.bak.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
Copy-Item -LiteralPath $settings -Destination $backup -Force

try {
    $data = Get-Content -LiteralPath $settings -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $data.hooks) {
        Write-UninstallMsg "nothing to do: no hooks in $settings"
        exit 0
    }

    function Get-HookGroups($arr) {
        $groups = New-Object System.Collections.Generic.List[object]
        foreach ($item in @($arr)) {
            if ($null -eq $item) { continue }
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

    $hooksObj = [ordered]@{}
    foreach ($p in $data.hooks.PSObject.Properties) {
        $stripped = @(Strip-WakeupHooks $p.Value)
        if ($stripped.Count -gt 0) {
            $hooksObj[$p.Name] = $stripped
        }
    }

    if ($hooksObj.Count -eq 0) {
        $data.PSObject.Properties.Remove('hooks')
    } else {
        $data.hooks = [pscustomobject]$hooksObj
    }

    $tmp = "$settings.tmp.$PID"
    $json = ($data | ConvertTo-Json -Depth 20)
    [System.IO.File]::WriteAllText($tmp, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    $null = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
    Move-Item -LiteralPath $tmp -Destination $settings -Force
}
catch {
    Write-Error "Could not update Claude settings. Your existing settings were not changed."
    Write-WakeupEngineLog ("uninstall failed: {0}" -f $_.Exception.Message)
    throw
}

Write-UninstallMsg "removed from -> $settings"
Write-UninstallMsg "backup       -> $backup"
