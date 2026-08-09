# Launch the Claude Wakeup Alarm management UI (WPF, STA).
# Double-click this file, or run: .\Launch-WakeupAlarm.ps1
# Prefer Launch-WakeupAlarm.cmd for reliable double-click from Explorer.

$ErrorActionPreference = 'Stop'
$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ui = Join-Path $root 'ui\WakeupAlarmUI.ps1'

if (-not (Test-Path -LiteralPath $ui)) {
    [System.Windows.Forms.MessageBox]::Show("UI script not found:`n$ui", 'Claude Wakeup Alarm') | Out-Null
    exit 1
}

# If this host is not STA, re-launch correctly and exit (Explorer double-click is often MTA).
$apt = [System.Threading.Thread]::CurrentThread.GetApartmentState()
if ($apt -ne 'STA') {
    $argList = "-STA -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WorkingDirectory $root | Out-Null
    exit 0
}

# Already STA: run the manager in this process so the window stays attached.
Set-Location -LiteralPath $root
$env:WAKEUP_HOME = $root
& $ui
