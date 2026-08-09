# Smoke test: load UI then auto-close
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$env:WAKEUP_HOME = $root
& powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'ui\WakeupAlarmUI.ps1') -SmokeClose
exit $LASTEXITCODE
