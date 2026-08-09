# Live playback test. Plays for real unless -DryWorker.
# Default: fake idle 60, then set idle 0 to prove return-stop.
# -Real: no idle faking - walk away from the keyboard.

[CmdletBinding()]
param(
    [switch]$Real
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Common.ps1')

Write-Host '=== wakeup live test ==='
$override = Join-Path $env:TEMP 'wakeup-idle-override.txt'
$env:WAKEUP_HOME = $root
$env:WAKEUP_LOCK = (Join-Path $env:TEMP ("wakeup-live-lock-" + [guid]::NewGuid().ToString('n')))
$env:WAKEUP_LOG = (Join-Path $env:TEMP 'wakeup-live-test.log')

if (-not $Real) {
    Set-Content -LiteralPath $override -Value '60' -Encoding ASCII
    $env:WAKEUP_IDLE_OVERRIDE_FILE = $override
}

$play = Join-Path $root 'lib\Play.ps1'
Write-Host 'Starting alarm (Immediate + ForcePlay)...'
$p = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$play`" -Trigger permission_prompt -Immediate -ForcePlay" -PassThru

Start-Sleep -Seconds 3
if (-not $Real) {
    Write-Host 'Simulating return (idle=0)...'
    Set-Content -LiteralPath $override -Value '0' -Encoding ASCII
}

$sw = [Diagnostics.Stopwatch]::StartNew()
while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt 30) {
    Start-Sleep -Milliseconds 500
    $p.Refresh()
}

if ($p.HasExited) {
    Write-Host "PASS  worker exited after return/stop (exit=$($p.ExitCode))" -ForegroundColor Green
} else {
    Write-Host 'FAIL  worker still running' -ForegroundColor Red
    try { $p.Kill() } catch {}
    exit 1
}

Remove-Item Env:WAKEUP_IDLE_OVERRIDE_FILE -ErrorAction SilentlyContinue
Remove-Item Env:WAKEUP_LOCK -ErrorAction SilentlyContinue
Remove-Item Env:WAKEUP_LOG -ErrorAction SilentlyContinue
Remove-Item Env:WAKEUP_HOME -ErrorAction SilentlyContinue
Remove-Item $override -ErrorAction SilentlyContinue
exit 0
