# Launch the Claude Wakeup Alarm management UI (WPF, STA).
# Usage: .\Launch-WakeupAlarm.ps1

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$ui = Join-Path $root 'ui\WakeupAlarmUI.ps1'

if (-not (Test-Path -LiteralPath $ui)) {
    Write-Error "UI script not found: $ui"
    exit 1
}

# Ensure STA apartment for WPF
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'powershell.exe'
$psi.Arguments = "-STA -NoProfile -ExecutionPolicy Bypass -File `"$ui`""
$psi.WorkingDirectory = $root
$psi.UseShellExecute = $false
$p = [System.Diagnostics.Process]::Start($psi)
exit 0
