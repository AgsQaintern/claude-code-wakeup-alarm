# Shared helpers: idle detection, lock, video resolve, status, ffplay detection.
# Dot-sourced by wakeup.ps1 and lib/Play.ps1.

$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'Config.ps1')

$script:WakeupHome = Get-WakeupHome
$script:WakeupLastInputType = $null

function Initialize-WakeupIdleApi {
    if ($script:WakeupLastInputType) { return }
    $code = @'
using System;
using System.Runtime.InteropServices;
public static class WakeupIdle {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    [DllImport("kernel32.dll")]
    public static extern uint GetTickCount();
    public static int IdleSeconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (!GetLastInputInfo(ref lii)) return 999;
        uint idleMs = GetTickCount() - lii.dwTime;
        return (int)(idleMs / 1000u);
    }
}
'@
    try {
        Add-Type -TypeDefinition $code -ErrorAction Stop | Out-Null
        $script:WakeupLastInputType = $true
    } catch {
        # type may already exist
        $script:WakeupLastInputType = $true
    }
}

function Get-WakeupIdleSeconds {
    if ($env:WAKEUP_IDLE_OVERRIDE_FILE -and (Test-Path -LiteralPath $env:WAKEUP_IDLE_OVERRIDE_FILE)) {
        try {
            $t = (Get-Content -LiteralPath $env:WAKEUP_IDLE_OVERRIDE_FILE -Raw).Trim()
            return [int]$t
        } catch { return 0 }
    }
    if ($env:WAKEUP_IDLE_OVERRIDE) {
        try { return [int]$env:WAKEUP_IDLE_OVERRIDE } catch { return 0 }
    }
    try {
        Initialize-WakeupIdleApi
        return [WakeupIdle]::IdleSeconds()
    } catch {
        return 999
    }
}

function Test-WakeupLockHeld {
    param([string]$LockPath = (Get-WakeupLockPath))
    if (-not (Test-Path -LiteralPath $LockPath)) { return $false }
    $pidFile = Join-Path $LockPath 'pid'
    if (-not (Test-Path -LiteralPath $pidFile)) { return $false }
    try {
        $ownerPid = [int]((Get-Content -LiteralPath $pidFile -Raw).Trim())
        $proc = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
        return [bool]$proc
    } catch {
        return $false
    }
}

function Acquire-WakeupLock {
    param([string]$LockPath = (Get-WakeupLockPath))
    try {
        $null = New-Item -ItemType Directory -Path $LockPath -ErrorAction Stop
        Set-Content -LiteralPath (Join-Path $LockPath 'pid') -Value $PID -Encoding ASCII
        return $true
    } catch {
        if (Test-WakeupLockHeld -LockPath $LockPath) { return $false }
        Remove-Item -LiteralPath $LockPath -Recurse -Force -ErrorAction SilentlyContinue
        try {
            $null = New-Item -ItemType Directory -Path $LockPath -ErrorAction Stop
            Set-Content -LiteralPath (Join-Path $LockPath 'pid') -Value $PID -Encoding ASCII
            return $true
        } catch {
            return $false
        }
    }
}

function Release-WakeupLock {
    param([string]$LockPath = (Get-WakeupLockPath))
    Remove-Item -LiteralPath $LockPath -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-WakeupMediaExtensions {
    return @('*.mp4','*.mkv','*.mov','*.webm','*.MP4','*.MKV','*.MOV','*.WEBM')
}

function Get-WakeupMediaFiles {
    param([string]$HomePath = $script:WakeupHome)
    $media = Join-Path $HomePath 'media'
    if (-not (Test-Path -LiteralPath $media)) { return @() }
    $files = @()
    foreach ($pat in (Get-WakeupMediaExtensions)) {
        $files += Get-ChildItem -LiteralPath $media -Filter $pat -File -ErrorAction SilentlyContinue
    }
    return @($files | Sort-Object FullName -Unique)
}

function Resolve-WakeupVideo {
    param([hashtable]$Config)
    if ($Config.videoMode -eq 'fixed' -or ($Config.video -and $Config.videoMode -ne 'random')) {
        $v = [string]$Config.video
        if ($v -and (Test-Path -LiteralPath $v)) { return $v }
    }
    if ($Config.video -and (Test-Path -LiteralPath ([string]$Config.video)) -and $Config.videoMode -eq 'fixed') {
        return [string]$Config.video
    }
    # random or empty fixed path
    if ($Config.video -and (Test-Path -LiteralPath ([string]$Config.video)) -and $Config.videoMode -ne 'random') {
        return [string]$Config.video
    }
    $clips = @(Get-WakeupMediaFiles)
    if ($clips.Count -eq 0) {
        if ($Config.video -and (Test-Path -LiteralPath ([string]$Config.video))) {
            return [string]$Config.video
        }
        return $null
    }
    if ($Config.videoMode -eq 'fixed' -and $Config.video) {
        $match = $clips | Where-Object { $_.FullName -eq $Config.video -or $_.Name -eq (Split-Path $Config.video -Leaf) } | Select-Object -First 1
        if ($match) { return $match.FullName }
    }
    $idx = Get-Random -Maximum $clips.Count
    return $clips[$idx].FullName
}

function Test-WakeupFFplay {
    $cmd = Get-Command ffplay -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # common chocolatey / scoop locations
    foreach ($p in @(
        "$env:ProgramFiles\ffmpeg\bin\ffplay.exe",
        "${env:ProgramFiles(x86)}\ffmpeg\bin\ffplay.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffplay.exe",
        "$env:USERPROFILE\scoop\shims\ffplay.exe"
    )) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Resolve-WakeupPlayerMode {
    param([hashtable]$Config)
    $mode = [string]$Config.player
    if ($mode -eq 'windows') { return 'windows' }
    if ($mode -eq 'ffplay') {
        if (Test-WakeupFFplay) { return 'ffplay' }
        return 'windows'
    }
    # auto
    if (Test-WakeupFFplay) { return 'ffplay' }
    return 'windows'
}

function Write-WakeupStatus {
    param(
        [string]$State,
        [string]$Trigger = '',
        [string]$Video = '',
        [int]$IdleSecs = -1,
        [string]$Message = ''
    )
    try {
        $obj = [ordered]@{
            state     = $State
            trigger   = $Trigger
            video     = $Video
            idleSecs  = $IdleSecs
            message   = $Message
            pid       = $PID
            updatedAt = (Get-Date).ToString('o')
        }
        $path = Get-WakeupStatusPath
        $json = ($obj | ConvertTo-Json -Compress)
        [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
    } catch {}
}

function Clear-WakeupStatus {
    try {
        $path = Get-WakeupStatusPath
        if (Test-Path -LiteralPath $path) {
            $obj = [ordered]@{
                state     = 'idle'
                trigger   = ''
                video     = ''
                idleSecs  = (Get-WakeupIdleSeconds)
                message   = ''
                pid       = 0
                updatedAt = (Get-Date).ToString('o')
            }
            [System.IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
        }
    } catch {}
}

function Read-WakeupStatus {
    $path = Get-WakeupStatusPath
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{ state = 'idle'; trigger = ''; video = ''; idleSecs = -1; message = ''; pid = 0 }
    }
    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return [pscustomobject]@{ state = 'idle'; trigger = ''; video = ''; idleSecs = -1; message = ''; pid = 0 }
    }
}

function Get-ClaudeCodeInfo {
    $info = [ordered]@{ Found = $false; Version = ''; Path = ''; SettingsFound = $false; SettingsPath = '' }
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) {
        $info.Found = $true
        $info.Path = $cmd.Source
        try {
            $ver = & claude --version 2>$null
            if ($ver) { $info.Version = ([string]$ver).Trim() }
        } catch {}
    }
    $settings = Join-Path $env:USERPROFILE '.claude\settings.json'
    $info.SettingsPath = $settings
    $info.SettingsFound = Test-Path -LiteralPath $settings
    return [pscustomobject]$info
}

function Test-WakeupHooksInstalled {
    param(
        [ValidateSet('global','project')]
        [string]$Scope = 'global',
        [string]$ProjectPath = ''
    )
    if ($Scope -eq 'project') {
        if (-not $ProjectPath) { return $false }
        $settings = Join-Path $ProjectPath '.claude\settings.json'
    } else {
        $settings = Join-Path $env:USERPROFILE '.claude\settings.json'
    }
    if (-not (Test-Path -LiteralPath $settings)) { return $false }
    try {
        $raw = Get-Content -LiteralPath $settings -Raw -Encoding UTF8
        return ($raw -match 'wakeup\.ps1')
    } catch {
        return $false
    }
}

function Get-WakeupHookCommand {
    param([string]$HomePath = $script:WakeupHome)
    $scriptPath = Join-Path $HomePath 'wakeup.ps1'
    return "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
}
