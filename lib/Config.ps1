# Config load / validate / atomic save for config.json
# Shared by the alarm engine and the WPF manager.

$script:WakeupConfigSchemaVersion = 1

function Get-WakeupHome {
    if ($env:WAKEUP_HOME -and (Test-Path -LiteralPath $env:WAKEUP_HOME)) {
        return (Resolve-Path -LiteralPath $env:WAKEUP_HOME).Path
    }
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
    return (Resolve-Path -LiteralPath (Join-Path $here '..')).Path
}

function Get-WakeupConfigPath {
    param([string]$HomePath = (Get-WakeupHome))
    return (Join-Path $HomePath 'config.json')
}

function New-WakeupDefaultConfig {
    [pscustomobject]@{
        enabled   = $true
        delaySecs = 10
        idleSecs  = 15
        returnSecs = 2
        maxSecs   = 120
        loop      = $false
        events    = @(
            'permission_prompt'
            'idle_prompt'
            'agent_needs_input'
            'agent_completed'
            'stop'
        )
        video     = ''
        videoMode = 'random'
        player    = 'auto'
        volume    = $null
        logPath   = ''
        ui        = [pscustomobject]@{
            firstRunCompleted = $false
            minimizeToTray    = $true
            startAtLogin      = $false
            scope             = 'global'
            projectPath       = ''
        }
    }
}

function ConvertTo-WakeupHashtable {
    param($Object)
    if ($null -eq $Object) { return $null }
    if ($Object -is [hashtable]) { return $Object }
    if ($Object -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $Object.Keys) { $h[$k] = ConvertTo-WakeupHashtable $Object[$k] }
        return $h
    }
    if ($Object -is [string] -or $Object -is [ValueType]) {
        return $Object
    }
    if ($Object -is [System.Collections.IEnumerable]) {
        $list = @()
        foreach ($item in $Object) { $list += ,(ConvertTo-WakeupHashtable $item) }
        return $list
    }
    if ($Object -is [psobject]) {
        $props = @($Object.PSObject.Properties)
        if ($props.Count -gt 0) {
            $h = @{}
            foreach ($p in $props) {
                $h[$p.Name] = ConvertTo-WakeupHashtable $p.Value
            }
            return $h
        }
    }
    return $Object
}

function Merge-WakeupConfig {
    param($Defaults, $Loaded)
    $result = ConvertTo-WakeupHashtable $Defaults
    $src = ConvertTo-WakeupHashtable $Loaded
    if (-not $src) { return $result }
    foreach ($key in $src.Keys) {
        if ($key -eq 'ui' -and $result.ContainsKey('ui') -and ($src[$key] -is [hashtable])) {
            foreach ($uk in $src[$key].Keys) {
                $result.ui[$uk] = $src[$key][$uk]
            }
        } else {
            $result[$key] = $src[$key]
        }
    }
    return $result
}

function Test-WakeupConfig {
    param([hashtable]$Config)
    $errors = @()
    foreach ($n in @('delaySecs','idleSecs','returnSecs','maxSecs')) {
        if (-not ($Config.ContainsKey($n))) { $errors += "Missing $n"; continue }
        $v = [int]$Config[$n]
        if ($v -lt 0 -or $v -gt 3600) { $errors += "$n must be 0-3600" }
        $Config[$n] = $v
    }
    if ($Config.maxSecs -lt 1) { $errors += 'maxSecs must be >= 1' }
    $validEvents = @('permission_prompt','idle_prompt','agent_needs_input','agent_completed','stop')
    if ($Config.events -isnot [System.Collections.IEnumerable] -or ($Config.events -is [string])) {
        $errors += 'events must be an array'
    } else {
        $clean = @()
        foreach ($e in @($Config.events)) {
            if ($validEvents -contains [string]$e) { $clean += [string]$e }
        }
        $Config.events = $clean
    }
    $player = [string]$Config.player
    if (@('auto','ffplay','windows','quicktime') -notcontains $player) {
        $errors += "player must be auto|ffplay|windows|quicktime"
    }
    $mode = [string]$Config.videoMode
    if (@('random','fixed') -notcontains $mode) {
        $Config.videoMode = if ([string]$Config.video) { 'fixed' } else { 'random' }
    }
    $Config.enabled = [bool]$Config.enabled
    $Config.loop = [bool]$Config.loop
    if (-not $Config.ui) { $Config.ui = @{} }
    if ($Config.ui -isnot [hashtable]) { $Config.ui = ConvertTo-WakeupHashtable $Config.ui }
    # Migrate legacy startWithWindows -> startAtLogin
    if ($Config.ui.ContainsKey('startWithWindows') -and -not $Config.ui.ContainsKey('startAtLogin')) {
        $Config.ui.startAtLogin = [bool]$Config.ui.startWithWindows
    }
    if (-not $Config.ui.ContainsKey('startAtLogin')) {
        $Config.ui.startAtLogin = $false
    }
    # Keep legacy key mirrored for older UI bindings during transition
    $Config.ui.startWithWindows = [bool]$Config.ui.startAtLogin
    if ($Config.ContainsKey('volume') -and $null -ne $Config.volume -and [string]$Config.volume -ne '') {
        try {
            $vol = [int]$Config.volume
            if ($vol -lt 0 -or $vol -gt 100) { $errors += 'volume must be 0-100 or empty' }
            else { $Config.volume = $vol }
        } catch {
            $errors += 'volume must be 0-100 or empty'
        }
    }
    return ,@($errors)
}

function Read-WakeupConfig {
    param([string]$Path = (Get-WakeupConfigPath))
    $defaults = ConvertTo-WakeupHashtable (New-WakeupDefaultConfig)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $defaults
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $defaults }
        $loaded = $raw | ConvertFrom-Json
        $merged = Merge-WakeupConfig -Defaults $defaults -Loaded $loaded
        $null = Test-WakeupConfig -Config $merged
        return $merged
    } catch {
        Write-WakeupEngineLog "WARN config read failed: $($_.Exception.Message)" -Config $defaults
        return $defaults
    }
}

function ConvertTo-WakeupJson {
    param($Object, [int]$Depth = 8)
    # Prefer native ConvertTo-Json; normalize booleans/numbers via PSCustomObject roundtrip
    ($Object | ConvertTo-Json -Depth $Depth)
}

function Write-WakeupConfig {
    param(
        [hashtable]$Config,
        [string]$Path = (Get-WakeupConfigPath),
        [switch]$Backup
    )
    $errors = Test-WakeupConfig -Config $Config
    if ($errors.Count -gt 0) {
        throw "Invalid configuration: $($errors -join '; ')"
    }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if ($Backup -and (Test-Path -LiteralPath $Path)) {
        $bak = "$Path.bak.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
        Copy-Item -LiteralPath $Path -Destination $bak -Force
    }
    # Build a clean PSCustomObject for stable JSON
    $startAtLogin = $false
    if ($Config.ui.ContainsKey('startAtLogin')) {
        $startAtLogin = [bool]$Config.ui.startAtLogin
    } elseif ($Config.ui.ContainsKey('startWithWindows')) {
        $startAtLogin = [bool]$Config.ui.startWithWindows
    }
    $volOut = $null
    if ($Config.ContainsKey('volume') -and $null -ne $Config.volume -and [string]$Config.volume -ne '') {
        $volOut = [int]$Config.volume
    }
    $obj = [ordered]@{
        enabled    = [bool]$Config.enabled
        delaySecs  = [int]$Config.delaySecs
        idleSecs   = [int]$Config.idleSecs
        returnSecs = [int]$Config.returnSecs
        maxSecs    = [int]$Config.maxSecs
        loop       = [bool]$Config.loop
        events     = @($Config.events)
        video      = [string]$Config.video
        videoMode  = [string]$Config.videoMode
        player     = [string]$Config.player
        volume     = $volOut
        logPath    = [string]$Config.logPath
        ui         = [ordered]@{
            firstRunCompleted = [bool]$Config.ui.firstRunCompleted
            minimizeToTray    = [bool]$Config.ui.minimizeToTray
            startAtLogin      = $startAtLogin
            scope             = [string]$Config.ui.scope
            projectPath       = [string]$Config.ui.projectPath
        }
    }
    $json = ($obj | ConvertTo-Json -Depth 8)
    $tmp = "$Path.tmp.$PID"
    [System.IO.File]::WriteAllText($tmp, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-WakeupLogPath {
    param([hashtable]$Config = $null)
    if (-not $Config) { $Config = Read-WakeupConfig }
    if ($env:WAKEUP_LOG) { return $env:WAKEUP_LOG }
    if ($Config.logPath) { return [string]$Config.logPath }
    return (Join-Path $env:USERPROFILE '.claude\wakeup.log')
}

function Get-WakeupLockPath {
    if ($env:WAKEUP_LOCK) { return $env:WAKEUP_LOCK }
    return (Join-Path $env:TEMP 'claude-wakeup.lock')
}

function Get-WakeupStatusPath {
    if ($env:WAKEUP_STATUS) { return $env:WAKEUP_STATUS }
    return (Join-Path $env:TEMP 'claude-wakeup.status.json')
}

function Write-WakeupEngineLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        $Config = $null
    )
    try {
        $logPath = Get-WakeupLogPath -Config $Config
        $dir = Split-Path -Parent $logPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # never throw from logging
    }
}
