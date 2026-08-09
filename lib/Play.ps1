# Detached worker: grace period -> idle gate -> play -> stop on return.
# Invoked by wakeup.ps1 via Start-Process. Args: -Trigger <eventKey> [-Immediate] [-ForcePlay]

param(
    [Parameter(Mandatory = $false)]
    [string]$Trigger = 'unknown',

    [switch]$Immediate,

    [switch]$ForcePlay,

    [string]$VideoOverride = '',

    [switch]$PreviewOnly
)

$ErrorActionPreference = 'Continue'
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'Common.ps1')

$Config = Read-WakeupConfig
$LockPath = Get-WakeupLockPath
$script:PlayerProcess = $null
$script:PlayerMode = 'windows'
$script:WindowsPlayerJob = $null
$script:OwnedPlayerPids = @()

function Stop-WakeupOwnedPlayers {
    if ($script:PlayerProcess -and -not $script:PlayerProcess.HasExited) {
        try { $script:PlayerProcess.Kill() } catch {}
        try { $script:PlayerProcess.WaitForExit(2000) | Out-Null } catch {}
    }
    $script:PlayerProcess = $null
    foreach ($p in @($script:OwnedPlayerPids)) {
        try {
            $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -match '^(ffplay|powershell)$') {
                Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    $script:OwnedPlayerPids = @()
}

function Start-WakeupFFplay {
    param([string]$VideoPath)
    $ff = Test-WakeupFFplay
    if (-not $ff) { return $false }
    $p = Start-Process -FilePath $ff -ArgumentList @('-fs','-autoexit','-loglevel','quiet', $VideoPath) -PassThru -WindowStyle Hidden
    $script:PlayerProcess = $p
    $script:OwnedPlayerPids += $p.Id
    return $true
}

function Start-WakeupWindowsPlayer {
    param([string]$VideoPath)
    # Build a real PowerShell script (single-quoted here-strings do NOT turn '' into ')
    $videoLiteral = $VideoPath.Replace("'", "''")
    $tmp = Join-Path $env:TEMP ("wakeup-player-{0}.ps1" -f $PID)
    $script = @"
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
`$video = '$videoLiteral'
`$w = New-Object System.Windows.Window
`$w.WindowStyle = 'None'
`$w.ResizeMode = 'NoResize'
`$w.WindowState = 'Maximized'
`$w.Topmost = `$true
`$w.Background = [System.Windows.Media.Brushes]::Black
`$w.ShowInTaskbar = `$false
`$m = New-Object System.Windows.Controls.MediaElement
`$m.Source = [Uri]`$video
`$m.LoadedBehavior = 'Manual'
`$m.UnloadedBehavior = 'Close'
`$m.Stretch = 'Uniform'
`$m.Volume = 1.0
`$w.Content = `$m
`$m.Add_MediaEnded({ `$w.Close() })
`$m.Add_MediaFailed({
    param(`$s, `$e)
    `$msg = 'Could not play video'
    try { if (`$e.ErrorException) { `$msg = `$e.ErrorException.Message } } catch {}
    try { [System.Windows.MessageBox]::Show(`$msg, 'Wakeup Alarm') } catch {}
    `$w.Close()
})
`$w.Add_Loaded({
    `$w.Activate()
    `$m.Play()
})
`$w.Add_KeyDown({ param(`$s, `$e) `$w.Close() })
`$w.Add_MouseDown({ `$w.Close() })
[void]`$w.ShowDialog()
"@
    Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -File `"$tmp`"" -PassThru -WindowStyle Normal
    $script:PlayerProcess = $p
    $script:OwnedPlayerPids += $p.Id
    Start-Job -ScriptBlock {
        param($pidToWait, $file)
        try { Wait-Process -Id $pidToWait -ErrorAction SilentlyContinue } catch {}
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    } -ArgumentList $p.Id, $tmp | Out-Null
    return $true
}

function Test-WakeupPlayerRunning {
    if ($script:PlayerProcess) {
        try {
            $script:PlayerProcess.Refresh()
            return -not $script:PlayerProcess.HasExited
        } catch { return $false }
    }
    return $false
}

function Start-WakeupPlayer {
    param([string]$VideoPath, [string]$Mode)
    $script:PlayerMode = $Mode
    if ($Mode -eq 'ffplay') {
        if (Start-WakeupFFplay -VideoPath $VideoPath) { return $true }
        Write-WakeupEngineLog 'ffplay not available - using Windows player' -Config $Config
        $script:PlayerMode = 'windows'
    }
    return (Start-WakeupWindowsPlayer -VideoPath $VideoPath)
}

function Invoke-WakeupCleanup {
    Stop-WakeupOwnedPlayers
    Release-WakeupLock -LockPath $LockPath
    Clear-WakeupStatus
}

try {
    if (-not (Acquire-WakeupLock -LockPath $LockPath)) {
        Write-WakeupEngineLog "skip $Trigger (another alarm holds the lock)" -Config $Config
        exit 0
    }

    Write-WakeupStatus -State 'armed' -Trigger $Trigger -IdleSecs (Get-WakeupIdleSeconds)

    $delay = [int]$Config.delaySecs
    if ($Immediate) { $delay = 0 }

    if ($delay -gt 0) {
        Write-WakeupEngineLog "armed by $Trigger - waiting ${delay}s" -Config $Config
        Start-Sleep -Seconds $delay
    } else {
        Write-WakeupEngineLog "armed by $Trigger - immediate" -Config $Config
    }

    $idle = Get-WakeupIdleSeconds
    $needIdle = [int]$Config.idleSecs
    if (-not $ForcePlay -and -not $PreviewOnly -and ($idle -lt $needIdle)) {
        Write-WakeupEngineLog "skipped: you're here (idle ${idle}s < ${needIdle}s)" -Config $Config
        exit 0
    }

    $video = $VideoOverride
    if (-not $video) { $video = Resolve-WakeupVideo -Config $Config }
    if (-not $video -or -not (Test-Path -LiteralPath $video)) {
        Write-WakeupEngineLog ("WARN nothing to play (video='{0}', no clips in media/?)" -f $Config.video) -Config $Config
        exit 0
    }

    if ($env:WAKEUP_DRY_RUN -eq '1') {
        Write-WakeupEngineLog "PLAY $video (dry run, trigger=$Trigger, idle=${idle}s)" -Config $Config
        Write-WakeupStatus -State 'idle' -Trigger $Trigger -Video $video -IdleSecs $idle -Message 'dry-run'
        exit 0
    }

    if (-not $Config.enabled -and -not $ForcePlay -and -not $PreviewOnly) {
        Write-WakeupEngineLog "skip $Trigger (alarm disabled)" -Config $Config
        exit 0
    }

    $mode = Resolve-WakeupPlayerMode -Config $Config
    Write-WakeupEngineLog "PLAY $video (trigger=$Trigger, idle=${idle}s, player=$mode)" -Config $Config
    Write-WakeupStatus -State 'playing' -Trigger $Trigger -Video $video -IdleSecs $idle

    $deadline = [DateTime]::UtcNow.AddSeconds([int]$Config.maxSecs)
    $returnSecs = [int]$Config.returnSecs

    # TEST / ForcePlay runs while you are at the desk. Do NOT use idle "you're back"
    # detection here - that would kill the video after a few seconds of watching.
    # Stop via: click/key on the player window, video end, or maxSecs.
    # Real Claude hooks (no -ForcePlay) still stop as soon as idle drops below returnSecs.
    $useIdleReturn = -not $ForcePlay -and -not $PreviewOnly

    do {
        if (-not (Start-WakeupPlayer -VideoPath $video -Mode $mode)) {
            Write-WakeupEngineLog 'WARN failed to start player' -Config $Config
            break
        }
        while (Test-WakeupPlayerRunning) {
            $idleNow = Get-WakeupIdleSeconds
            Write-WakeupStatus -State 'playing' -Trigger $Trigger -Video $video -IdleSecs $idleNow
            if ($useIdleReturn -and ($idleNow -lt $returnSecs)) {
                Write-WakeupEngineLog "you're back - stopping" -Config $Config
                exit 0
            }
            if ([DateTime]::UtcNow -ge $deadline) {
                Write-WakeupEngineLog ("hit maxSecs ({0}s) - stopping" -f $Config.maxSecs) -Config $Config
                exit 0
            }
            Start-Sleep -Seconds 1
        }
        $shouldLoop = [bool]$Config.loop -and ([DateTime]::UtcNow -lt $deadline) -and -not $PreviewOnly -and -not $ForcePlay
    } while ($shouldLoop)

    Write-WakeupEngineLog 'played through' -Config $Config
}
catch {
    Write-WakeupEngineLog ("WARN worker error: {0}" -f $_.Exception.Message) -Config $Config
}
finally {
    Invoke-WakeupCleanup
}
