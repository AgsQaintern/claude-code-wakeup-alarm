# Claude Code hook entrypoint (Windows PowerShell).
# Must return quickly and always exit 0 so a broken alarm never blocks Claude.

$ErrorActionPreference = 'Continue'
$exitCode = 0

try {
    $root = $PSScriptRoot
    if (-not $root) { $root = Split-Path -Parent $MyInvocation.MyCommand.Path }
    . (Join-Path $root 'lib\Common.ps1')

    $Config = Read-WakeupConfig
    if (-not $Config.enabled) { exit 0 }

    $payload = ''
    try {
        if ($Host.Name -or $true) {
            $payload = [Console]::In.ReadToEnd()
        }
    } catch {
        $payload = ''
    }
    if ([string]::IsNullOrWhiteSpace($payload)) {
        # fallback for some hosts
        try { $payload = ($input | Out-String) } catch { $payload = '' }
    }

    $key = ''
    try {
        $json = $payload | ConvertFrom-Json -ErrorAction Stop
        $event = [string]$json.hook_event_name
        $ntype = [string]$json.notification_type
        switch ($event) {
            'Stop'         { $key = 'stop' }
            'Notification' { $key = $ntype }
            default        { $key = '' }
        }
    } catch {
        exit 0
    }

    if (-not $key) { exit 0 }

    $events = @($Config.events)
    if ($events -notcontains $key) { exit 0 }

    if (Test-WakeupLockHeld) {
        Write-WakeupEngineLog "skip $key (an alarm is already armed)" -Config $Config
        exit 0
    }

    $playScript = Join-Path $root 'lib\Play.ps1'
    $logPath = Get-WakeupLogPath -Config $Config
    $logDir = Split-Path -Parent $logPath
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    # Single ArgumentList string so paths with spaces stay quoted
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$playScript`" -Trigger `"$key`""
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden | Out-Null
}
catch {
    # never fail the hook
}
finally {
    exit 0
}
