# Claude Wakeup Alarm - WPF Management UI
# Configuration shell only. Alarm logic lives in wakeup.ps1 / lib/Play.ps1.

param(
    [switch]$SmokeClose
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

$script:UiRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if ($env:WAKEUP_HOME -and (Test-Path -LiteralPath $env:WAKEUP_HOME)) {
    $script:AppRoot = (Resolve-Path -LiteralPath $env:WAKEUP_HOME).Path
} else {
    $script:AppRoot = Split-Path -Parent $script:UiRoot
}
$env:WAKEUP_HOME = $script:AppRoot

. (Join-Path $script:AppRoot 'lib\Common.ps1')

$script:Window = $null
$script:Config = $null
$script:SuppressEvents = $false
$script:Tray = $null
$script:ToastTimer = $null
$script:PollTimer = $null
$script:WizardStep = 0
$script:ReallyExit = $false
$script:NavButtons = @()
$script:Pages = @{}

function Show-Toast([string]$Message, [string]$Color = '#FF3DDC97') {
    $toast = $script:Window.FindName('ToastBar')
    $txt = $script:Window.FindName('TxtToast')
    if (-not $toast) { return }
    $txt.Text = $Message
    $txt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    $toast.Visibility = 'Visible'
    if ($script:ToastTimer) { $script:ToastTimer.Stop() }
    $script:ToastTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:ToastTimer.Interval = [TimeSpan]::FromSeconds(2.5)
    $script:ToastTimer.Add_Tick({
        $script:Window.FindName('ToastBar').Visibility = 'Collapsed'
        $script:ToastTimer.Stop()
    })
    $script:ToastTimer.Start()
}

function Get-UiProjectPath {
    $p = [string]$script:Config.ui.projectPath
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    return $script:AppRoot
}

function Save-UiConfig {
    param([switch]$Silent)
    try {
        Write-WakeupConfig -Config $script:Config
        if (-not $Silent) { Show-Toast 'Settings saved' }
    } catch {
        Write-WakeupEngineLog ("UI config save failed: {0}" -f $_.Exception.Message)
        Show-Toast 'Could not save settings. See logs for details.' '#FFFF6B7A'
    }
}

function Set-ActivePage([string]$Name) {
    foreach ($k in $script:Pages.Keys) {
        $script:Pages[$k].Visibility = if ($k -eq $Name) { 'Visible' } else { 'Collapsed' }
    }
    foreach ($btn in $script:NavButtons) {
        $active = ([string]$btn.Tag -eq $Name)
        $btn.Style = $script:Window.TryFindResource($(if ($active) { 'NavButtonActive' } else { 'NavButton' }))
    }
}

function Update-EventTogglesFromConfig {
    $script:SuppressEvents = $true
    $ev = @($script:Config.events)
    $script:Window.FindName('ChkEvPermission').IsChecked = ($ev -contains 'permission_prompt')
    $script:Window.FindName('ChkEvIdle').IsChecked = ($ev -contains 'idle_prompt')
    $script:Window.FindName('ChkEvNeedsInput').IsChecked = ($ev -contains 'agent_needs_input')
    $script:Window.FindName('ChkEvCompleted').IsChecked = ($ev -contains 'agent_completed')
    $script:Window.FindName('ChkEvStop').IsChecked = ($ev -contains 'stop')
    $script:SuppressEvents = $false
}

function Save-EventsFromUi {
    if ($script:SuppressEvents) { return }
    $list = @()
    if ($script:Window.FindName('ChkEvPermission').IsChecked) { $list += 'permission_prompt' }
    if ($script:Window.FindName('ChkEvIdle').IsChecked) { $list += 'idle_prompt' }
    if ($script:Window.FindName('ChkEvNeedsInput').IsChecked) { $list += 'agent_needs_input' }
    if ($script:Window.FindName('ChkEvCompleted').IsChecked) { $list += 'agent_completed' }
    if ($script:Window.FindName('ChkEvStop').IsChecked) { $list += 'stop' }
    $script:Config.events = $list
    Save-UiConfig -Silent
    Show-Toast 'Settings saved'
}

function Update-AlarmControlsFromConfig {
    $script:SuppressEvents = $true
    $script:Window.FindName('SldDelay').Value = [double]$script:Config.delaySecs
    $script:Window.FindName('SldIdle').Value = [double]$script:Config.idleSecs
    $script:Window.FindName('SldReturn').Value = [double]$script:Config.returnSecs
    $script:Window.FindName('SldMax').Value = [double]$script:Config.maxSecs
    $script:Window.FindName('ChkLoop').IsChecked = [bool]$script:Config.loop
    $script:Window.FindName('ChkEnabled').IsChecked = [bool]$script:Config.enabled
    $script:Window.FindName('ChkAlarmMaster').IsChecked = [bool]$script:Config.enabled
    $script:Window.FindName('LblDelay').Text = "$([int]$script:Config.delaySecs)s"
    $script:Window.FindName('LblIdle').Text = "$([int]$script:Config.idleSecs)s"
    $script:Window.FindName('LblReturn').Text = "$([int]$script:Config.returnSecs)s"
    $script:Window.FindName('LblMax').Text = "$([int]$script:Config.maxSecs)s"
    $script:SuppressEvents = $false
}

function Save-AlarmFromUi {
    $script:Config.delaySecs = [int]$script:Window.FindName('SldDelay').Value
    $script:Config.idleSecs = [int]$script:Window.FindName('SldIdle').Value
    $script:Config.returnSecs = [int]$script:Window.FindName('SldReturn').Value
    $script:Config.maxSecs = [int]$script:Window.FindName('SldMax').Value
    $script:Config.loop = [bool]$script:Window.FindName('ChkLoop').IsChecked
    $script:Config.enabled = [bool]$script:Window.FindName('ChkEnabled').IsChecked
    Save-UiConfig
    Refresh-Dashboard
}

function Refresh-VideoList {
    $list = $script:Window.FindName('ListVideos')
    $list.Items.Clear()
    foreach ($f in @(Get-WakeupMediaFiles -HomePath $script:AppRoot)) {
        [void]$list.Items.Add($f.FullName)
    }
    if ($script:Config.videoMode -eq 'fixed' -and $script:Config.video) {
        $script:Window.FindName('RadVideoFixed').IsChecked = $true
        $script:Window.FindName('TxtSelectedVideo').Text = [string]$script:Config.video
        if (Test-Path -LiteralPath ([string]$script:Config.video)) {
            $fi = Get-Item -LiteralPath ([string]$script:Config.video)
            $script:Window.FindName('TxtVideoInfo').Text = ('{0:N1} MB  |  {1}' -f ($fi.Length/1MB), $fi.Extension)
            $idx = $list.Items.IndexOf($fi.FullName)
            if ($idx -ge 0) { $list.SelectedIndex = $idx }
        }
    } else {
        $script:Window.FindName('RadVideoRandom').IsChecked = $true
        $script:Window.FindName('TxtSelectedVideo').Text = '(random from media/)'
        $script:Window.FindName('TxtVideoInfo').Text = ''
    }
    switch ([string]$script:Config.player) {
        'ffplay'  { $script:Window.FindName('RadPlayerFFplay').IsChecked = $true }
        'windows' { $script:Window.FindName('RadPlayerWindows').IsChecked = $true }
        default   { $script:Window.FindName('RadPlayerAuto').IsChecked = $true }
    }
    $ff = Test-WakeupFFplay
    if ($ff) {
        $script:Window.FindName('TxtFFplayStatus').Text = 'FFplay  Installed'
        $script:Window.FindName('TxtFFplayStatus').Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FF3DDC97')
    } else {
        $script:Window.FindName('TxtFFplayStatus').Text = 'FFplay  Not detected - Windows player will be used'
        $script:Window.FindName('TxtFFplayStatus').Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FF9AA3B5')
    }
}

function Save-VideoFromUi {
    if ($script:Window.FindName('RadVideoRandom').IsChecked) {
        $script:Config.videoMode = 'random'
        $script:Config.video = ''
    } else {
        $script:Config.videoMode = 'fixed'
        $sel = $script:Window.FindName('ListVideos').SelectedItem
        if ($sel) { $script:Config.video = [string]$sel }
    }
    if ($script:Window.FindName('RadPlayerFFplay').IsChecked) { $script:Config.player = 'ffplay' }
    elseif ($script:Window.FindName('RadPlayerWindows').IsChecked) { $script:Config.player = 'windows' }
    else { $script:Config.player = 'auto' }
    Save-UiConfig
    Refresh-VideoList
    Refresh-Dashboard
}

function Refresh-Logs {
    $grid = $script:Window.FindName('GridLogs')
    $logPath = Get-WakeupLogPath -Config $script:Config
    $rows = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    if (Test-Path -LiteralPath $logPath) {
        $lines = Get-Content -LiteralPath $logPath -Tail 200 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match '^(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+(.*)$') {
                $ts = $Matches[1]
                $msg = $Matches[2]
                $event = 'log'
                $result = $msg
                $idle = ''
                if ($msg -match 'armed by (\S+)') { $event = $Matches[1]; $result = 'Received' }
                elseif ($msg -match 'PLAY .+ trigger=(\S+)') { $event = $Matches[1]; $result = 'Alarm started' }
                elseif ($msg -match "you're back|you.re back") { $event = 'User returned'; $result = 'Alarm stopped' }
                elseif ($msg -match 'skipped:') { $event = 'Idle detected'; $result = $msg }
                if ($msg -match 'idle=(\d+)s') { $idle = "$($Matches[1]) sec" }
                elseif ($msg -match 'idle (\d+)s') { $idle = "$($Matches[1]) sec" }
                $rows.Add([pscustomobject]@{ Timestamp = $ts; Event = $event; Result = $result; 'Idle Time' = $idle }) | Out-Null
            }
        }
    }
    $grid.ItemsSource = $rows
}

function Refresh-Setup {
    $info = Get-ClaudeCodeInfo
    if ($info.Found) {
        $script:Window.FindName('TxtSetupClaude').Text = 'Detected'
        if ($info.Version) { $script:Window.FindName('TxtSetupClaude').Text = "Detected ($($info.Version))" }
    } else {
        $script:Window.FindName('TxtSetupClaude').Text = 'Not Detected'
    }
    $script:Window.FindName('TxtSetupSettings').Text = $(if ($info.SettingsFound) { 'Detected' } else { 'Not Found' })
    $g = Test-WakeupHooksInstalled -Scope global
    $p = Test-WakeupHooksInstalled -Scope project -ProjectPath (Get-UiProjectPath)
    $script:Window.FindName('TxtSetupGlobal').Text = $(if ($g) { 'Installed' } else { 'Not Installed' })
    $script:Window.FindName('TxtSetupProject').Text = $(if ($p) { 'Installed' } else { 'Not Installed' })
    $script:Window.FindName('TxtSetupCursor').Text = $(if ($g -or $p) { 'Ready' } else { 'Install hooks to enable' })
}

function Refresh-Dashboard {
    $info = Get-ClaudeCodeInfo
    if ($info.Found) {
        $script:Window.FindName('TxtDashClaude').Text = 'Connected'
        $script:Window.FindName('TxtDashClaudeVer').Text = $(if ($info.Version) { $info.Version } else { 'claude on PATH' })
    } else {
        $script:Window.FindName('TxtDashClaude').Text = 'Not Detected'
        $script:Window.FindName('TxtDashClaudeVer').Text = ''
    }

    $scope = [string]$script:Config.ui.scope
    if ($scope -ne 'project') { $scope = 'global' }
    $hooksOk = Test-WakeupHooksInstalled -Scope $scope -ProjectPath (Get-UiProjectPath)
    $script:Window.FindName('TxtDashHooks').Text = $(if ($hooksOk) { 'Installed' } else { 'Not Installed' })
    $script:Window.FindName('TxtDashAlarm').Text = $(if ($script:Config.enabled) { 'Enabled' } else { 'Disabled' })
    $script:Window.FindName('TxtAlarmToggleLabel').Text = $(if ($script:Config.enabled) { 'ON' } else { 'OFF' })
    $script:Window.FindName('ChkAlarmMaster').IsChecked = [bool]$script:Config.enabled

    $mode = Resolve-WakeupPlayerMode -Config $script:Config
    $script:Window.FindName('TxtDashPlayer').Text = $(if ($mode -eq 'ffplay') { 'FFplay' } else { 'Windows Fallback' })
    $script:Window.FindName('TxtDashConfig').Text = $(if ($scope -eq 'project') { 'Project' } else { 'Global' })
    $script:Window.FindName('TxtScopeBadge').Text = $scope.ToUpperInvariant()

    $idle = Get-WakeupIdleSeconds
    $script:Window.FindName('TxtDashIdle').Text = "$idle sec"

    # pills
    $script:Window.FindName('TxtPillAlarm').Text = $(if ($script:Config.enabled) { 'Alarm Enabled' } else { 'Alarm Disabled' })
    $script:Window.FindName('TxtPillAlarm').Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($script:Config.enabled) { '#FF3DDC97' } else { '#FF9AA3B5' }))
    $script:Window.FindName('TxtPillHooks').Text = $(if ($hooksOk) { 'Claude Hooks Installed' } else { 'Hooks Not Installed' })
    $script:Window.FindName('TxtPillHooks').Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($hooksOk) { '#FF3DDC97' } else { '#FFFFB020' }))
    $script:Window.FindName('TxtPillReady').Text = $(if ($hooksOk -and $script:Config.enabled) { 'Monitoring Ready' } else { 'Setup Needed' })
    $script:Window.FindName('TxtPillReady').Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($(if ($hooksOk -and $script:Config.enabled) { '#FF3DDC97' } else { '#FF9AA3B5' }))

    Refresh-LiveStatus
    Refresh-RecentActivity
}

function Refresh-LiveStatus {
    $idle = Get-WakeupIdleSeconds
    $st = Read-WakeupStatus
    $script:Window.FindName('TxtLiveIdle').Text = "$idle sec"
    $script:Window.FindName('TxtDashIdle').Text = "$idle sec"
    $state = [string]$st.state
    if (-not $state) { $state = 'idle' }
    $script:Window.FindName('TxtLiveAlarm').Text = $state.ToUpperInvariant()
    $script:Window.FindName('TxtLiveEvent').Text = $(if ($st.trigger) { [string]$st.trigger } else { '-' })
    $script:Window.FindName('TxtDashLastEvent').Text = $(if ($st.trigger) { [string]$st.trigger } else { $script:Window.FindName('TxtDashLastEvent').Text })
    $vid = [string]$st.video
    $script:Window.FindName('TxtLiveVideo').Text = $(if ($vid) { Split-Path $vid -Leaf } else { '-' })
    $locked = Test-WakeupLockHeld
    $script:Window.FindName('TxtLiveLock').Text = $(if ($locked) { 'Held' } else { 'Free' })
    $script:Window.FindName('TxtLiveWorker').Text = $(if ($locked -or $state -eq 'playing' -or $state -eq 'armed') { 'Running' } else { 'Idle' })
    if ($state -eq 'playing' -and $st.updatedAt) {
        $script:Window.FindName('TxtDashLastAlarm').Text = ([datetime]$st.updatedAt).ToLocalTime().ToString('HH:mm:ss')
    }
}

function Refresh-RecentActivity {
    $panel = $script:Window.FindName('ListRecentActivity')
    $panel.Items.Clear()
    $logPath = Get-WakeupLogPath -Config $script:Config
    if (-not (Test-Path -LiteralPath $logPath)) { return }
    $lines = Get-Content -LiteralPath $logPath -Tail 8 -ErrorAction SilentlyContinue
    foreach ($line in ($lines | Select-Object -Last 5)) {
        if ($line -match '^(\d{4}-\d{2}-\d{2}\s+)(\d{2}:\d{2}:\d{2})\s+(.*)$') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = "$($Matches[3])    $($Matches[2])"
            $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#FF9AA3B5')
            $tb.Margin = [System.Windows.Thickness]::new(0,0,0,6)
            $tb.FontSize = 12
            [void]$panel.Items.Add($tb)
        }
    }
}

function Invoke-TestAlarm {
    param([switch]$PreviewOnly, [string]$Video = '')
    $play = Join-Path $script:AppRoot 'lib\Play.ps1'
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$play`" -Trigger test_alarm -Immediate -ForcePlay"
    if ($PreviewOnly) { $argList += ' -PreviewOnly' }
    if ($Video) { $argList += " -VideoOverride `"$Video`"" }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Normal | Out-Null
    Show-Toast 'Alarm started - click the video or press a key to stop'
}

function Invoke-SimulateFixture([string]$Name) {
    $fixture = Join-Path $script:AppRoot "tests\fixtures\$Name"
    if (-not (Test-Path -LiteralPath $fixture)) {
        Show-Toast "Fixture missing: $Name" '#FFFF6B7A'
        return
    }
    $hook = Join-Path $script:AppRoot 'wakeup.ps1'
    $json = Get-Content -LiteralPath $fixture -Raw -Encoding UTF8
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$hook`""
    $psi.RedirectStandardInput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $script:AppRoot
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($json)
    $p.StandardInput.Close()
    Show-Toast "Simulated $Name via hook pipeline"
}

function Invoke-InstallHooks([string]$Scope) {
    $install = Join-Path $script:AppRoot 'install.ps1'
    try {
        if ($Scope -eq 'project') {
            $proj = Get-UiProjectPath
            if (-not (Test-Path -LiteralPath $proj)) {
                Show-Toast 'Select a valid project directory first.' '#FFFF6B7A'
                return
            }
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $install -Project -ProjectPath $proj -Quiet
        } else {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $install -Quiet
        }
        $script:Config = Read-WakeupConfig
        Show-Toast 'Hooks installed'
        Refresh-Setup
        Refresh-Dashboard
    } catch {
        Write-WakeupEngineLog ("UI install failed: {0}" -f $_.Exception.Message)
        Show-Toast 'Could not update Claude settings. Your existing settings were not changed.' '#FFFF6B7A'
    }
}

function Invoke-UninstallHooks([string]$Scope) {
    $msg = if ($Scope -eq 'project') {
        'Remove wakeup hooks from the current project Claude settings?'
    } else {
        'Remove wakeup hooks from your global Claude settings?'
    }
    $r = [System.Windows.MessageBox]::Show($msg, 'Confirm uninstall', 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }
    $uninstall = Join-Path $script:AppRoot 'uninstall.ps1'
    try {
        if ($Scope -eq 'project') {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstall -Project -ProjectPath (Get-UiProjectPath) -Quiet
        } else {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstall -Quiet
        }
        Show-Toast 'Hooks uninstalled'
        Refresh-Setup
        Refresh-Dashboard
    } catch {
        Write-WakeupEngineLog ("UI uninstall failed: {0}" -f $_.Exception.Message)
        Show-Toast 'Could not update Claude settings. Your existing settings were not changed.' '#FFFF6B7A'
    }
}

function Set-StartWithWindows([bool]$Enable) {
    $name = 'ClaudeWakeupAlarmManager'
    $launch = Join-Path $script:AppRoot 'Launch-WakeupAlarm.ps1'
    $cmd = "powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launch`""
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if ($Enable) {
        Set-ItemProperty -Path $runKey -Name $name -Value $cmd -Force
    } else {
        Remove-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue
    }
}

function Test-StartWithWindows {
    $name = 'ClaudeWakeupAlarmManager'
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    try {
        $v = (Get-ItemProperty -Path $runKey -Name $name -ErrorAction Stop).$name
        return [bool]$v
    } catch { return $false }
}

function Save-AppSettingsFromUi {
    if ($script:Window.FindName('RadScopeProject').IsChecked) {
        $script:Config.ui.scope = 'project'
        $script:Config.ui.projectPath = [string]$script:Window.FindName('TxtProjectPath').Text
    } else {
        $script:Config.ui.scope = 'global'
    }
    $start = [bool]$script:Window.FindName('ChkStartWithWindows').IsChecked
    $script:Config.ui.startAtLogin = $start
    $script:Config.ui.startWithWindows = $start
    $script:Config.ui.minimizeToTray = [bool]$script:Window.FindName('ChkMinimizeTray').IsChecked
    try {
        Set-StartWithWindows -Enable $start
    } catch {
        Write-WakeupEngineLog ("startup toggle failed: {0}" -f $_.Exception.Message)
        Show-Toast 'Could not update Start with Windows.' '#FFFF6B7A'
        return
    }
    Save-UiConfig
    Refresh-Dashboard
}

function Update-SettingsPageFromConfig {
    $script:SuppressEvents = $true
    if ([string]$script:Config.ui.scope -eq 'project') {
        $script:Window.FindName('RadScopeProject').IsChecked = $true
    } else {
        $script:Window.FindName('RadScopeGlobal').IsChecked = $true
    }
    $script:Window.FindName('TxtProjectPath').Text = [string](Get-UiProjectPath)
    $script:Window.FindName('ChkStartWithWindows').IsChecked = [bool](Test-StartWithWindows)
    $script:Window.FindName('ChkMinimizeTray').IsChecked = [bool]$script:Config.ui.minimizeToTray
    $script:SuppressEvents = $false
}

function Initialize-Tray {
    $script:Tray = New-Object System.Windows.Forms.NotifyIcon
    $script:Tray.Text = 'Claude Wakeup Alarm'
    $script:Tray.Icon = [System.Drawing.SystemIcons]::Application
    $script:Tray.Visible = $true
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $open = $menu.Items.Add('Open Claude Wakeup Alarm')
    $en = $menu.Items.Add('Enable Alarm')
    $dis = $menu.Items.Add('Disable Alarm')
    $test = $menu.Items.Add('Test Alarm')
    [void]$menu.Items.Add('-')
    $exit = $menu.Items.Add('Exit')
    $open.add_Click({ $script:Window.Show(); $script:Window.WindowState = 'Normal'; $script:Window.Activate() })
    $en.add_Click({
        $script:Config.enabled = $true
        Save-UiConfig -Silent
        Refresh-Dashboard
        Update-AlarmControlsFromConfig
    })
    $dis.add_Click({
        $script:Config.enabled = $false
        Save-UiConfig -Silent
        Refresh-Dashboard
        Update-AlarmControlsFromConfig
    })
    $test.add_Click({ Invoke-TestAlarm })
    $exit.add_Click({
        $script:ReallyExit = $true
        $script:Window.Close()
    })
    $script:Tray.ContextMenuStrip = $menu
    $script:Tray.add_DoubleClick({ $script:Window.Show(); $script:Window.WindowState = 'Normal'; $script:Window.Activate() })
}

function Show-WizardStep {
    $overlay = $script:Window.FindName('WizardOverlay')
    $overlay.Visibility = 'Visible'
    $step = $script:WizardStep
    $script:Window.FindName('TxtWizardStep').Text = "Step $($step + 1) of 5"
    switch ($step) {
        0 {
            $script:Window.FindName('TxtWizardTitle').Text = 'Detect Claude Code'
            $info = Get-ClaudeCodeInfo
            if ($info.Found) {
                $script:Window.FindName('TxtWizardBody').Text = 'Claude Code was found on your PATH.'
                $script:Window.FindName('TxtWizardStatus').Text = $(if ($info.Version) { "Claude Code  $($info.Version)" } else { 'Claude Code  Connected' })
            } else {
                $script:Window.FindName('TxtWizardBody').Text = 'Claude Code was not detected on PATH. You can still install hooks and use the alarm once Claude is available.'
                $script:Window.FindName('TxtWizardStatus').Text = 'Not detected (optional for setup)'
            }
            $script:Window.FindName('BtnWizardNext').Content = 'Next'
        }
        1 {
            $script:Window.FindName('TxtWizardTitle').Text = 'Choose alarm video'
            $clips = @(Get-WakeupMediaFiles -HomePath $script:AppRoot)
            $script:Window.FindName('TxtWizardBody').Text = 'A bundled alarm video is ready. Add more clips later from the Videos page.'
            $script:Window.FindName('TxtWizardStatus').Text = $(if ($clips.Count) { "Found $($clips.Count) video(s) in media/" } else { 'No videos yet - add one on the Videos page' })
            $script:Window.FindName('BtnWizardNext').Content = 'Next'
        }
        2 {
            $script:Window.FindName('TxtWizardTitle').Text = 'Choose notification events'
            $script:Window.FindName('TxtWizardBody').Text = 'Default events cover permission prompts, idle waits, agent input, agent completion, and Claude finished.'
            $script:Window.FindName('TxtWizardStatus').Text = 'You can change these anytime on the Events page.'
            $script:Window.FindName('BtnWizardNext').Content = 'Next'
        }
        3 {
            $script:Window.FindName('TxtWizardTitle').Text = 'Install hooks'
            $script:Window.FindName('TxtWizardBody').Text = 'Install global Claude Code hooks so the alarm works in every project. Existing settings are preserved.'
            $script:Window.FindName('TxtWizardStatus').Text = 'Click Next to install globally.'
            $script:Window.FindName('BtnWizardNext').Content = 'Install'
        }
        4 {
            $script:Window.FindName('TxtWizardTitle').Text = 'Test Alarm'
            $script:Window.FindName('TxtWizardBody').Text = 'Launch a test alarm now. Move the mouse or press a key to stop it.'
            $script:Window.FindName('TxtWizardStatus').Text = 'Click Finish to run the test and complete setup.'
            $script:Window.FindName('BtnWizardNext').Content = 'Finish'
        }
    }
    $script:Window.FindName('BtnWizardBack').IsEnabled = ($step -gt 0)
}

function Complete-Wizard {
    $script:Config.ui.firstRunCompleted = $true
    Save-UiConfig -Silent
    $script:Window.FindName('WizardOverlay').Visibility = 'Collapsed'
    Show-Toast 'Claude Wakeup Alarm is ready.'
    Refresh-Dashboard
}

function Bind-UiEvents {
    foreach ($btn in $script:NavButtons) {
        $btn.Add_Click({
            param($s,$e)
            Set-ActivePage ([string]$s.Tag)
            switch ([string]$s.Tag) {
                'Dashboard' { Refresh-Dashboard }
                'Videos' { Refresh-VideoList }
                'Logs' { Refresh-Logs }
                'Setup' { Refresh-Setup }
                'Settings' { Update-SettingsPageFromConfig }
                'Events' { Update-EventTogglesFromConfig }
                'Alarm' { Update-AlarmControlsFromConfig }
            }
        })
    }

    $script:Window.FindName('ChkAlarmMaster').Add_Checked({
        if ($script:SuppressEvents) { return }
        $script:Config.enabled = $true
        Save-UiConfig -Silent
        Update-AlarmControlsFromConfig
        Refresh-Dashboard
        Show-Toast 'Alarm enabled'
    })
    $script:Window.FindName('ChkAlarmMaster').Add_Unchecked({
        if ($script:SuppressEvents) { return }
        $script:Config.enabled = $false
        Save-UiConfig -Silent
        Update-AlarmControlsFromConfig
        Refresh-Dashboard
        Show-Toast 'Alarm disabled'
    })

    foreach ($n in @('ChkEvPermission','ChkEvIdle','ChkEvNeedsInput','ChkEvCompleted','ChkEvStop')) {
        $script:Window.FindName($n).Add_Click({ Save-EventsFromUi })
    }

    foreach ($pair in @(
        @{ S='SldDelay'; L='LblDelay' },
        @{ S='SldIdle'; L='LblIdle' },
        @{ S='SldReturn'; L='LblReturn' },
        @{ S='SldMax'; L='LblMax' }
    )) {
        $sld = $script:Window.FindName($pair.S)
        $lbl = $script:Window.FindName($pair.L)
        $sld.Add_ValueChanged({
            param($sender,$args)
            if ($script:SuppressEvents) { return }
            $name = $sender.Name
            $labelName = switch ($name) {
                'SldDelay' { 'LblDelay' }
                'SldIdle' { 'LblIdle' }
                'SldReturn' { 'LblReturn' }
                'SldMax' { 'LblMax' }
            }
            $script:Window.FindName($labelName).Text = "$([int]$sender.Value)s"
        })
    }

    $script:Window.FindName('BtnSaveAlarm').Add_Click({ Save-AlarmFromUi })
    $script:Window.FindName('BtnTestAlarm').Add_Click({ Invoke-TestAlarm })
    $script:Window.FindName('BtnSimPermission').Add_Click({ Invoke-SimulateFixture 'permission_prompt.json' })
    $script:Window.FindName('BtnSimNeedsInput').Add_Click({ Invoke-SimulateFixture 'agent_needs_input.json' })
    $script:Window.FindName('BtnSimCompleted').Add_Click({ Invoke-SimulateFixture 'agent_completed.json' })
    $script:Window.FindName('BtnSimFinished').Add_Click({ Invoke-SimulateFixture 'stop.json' })

    $script:Window.FindName('BtnBrowseVideo').Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = 'Videos|*.mp4;*.mkv;*.mov;*.webm|All files|*.*'
        $dlg.Title = 'Add alarm video'
        if ($dlg.ShowDialog()) {
            $media = Join-Path $script:AppRoot 'media'
            if (-not (Test-Path $media)) { New-Item -ItemType Directory -Path $media | Out-Null }
            $dest = Join-Path $media (Split-Path $dlg.FileName -Leaf)
            Copy-Item -LiteralPath $dlg.FileName -Destination $dest -Force
            $script:Config.videoMode = 'fixed'
            $script:Config.video = $dest
            Save-UiConfig -Silent
            Refresh-VideoList
            Show-Toast 'Video added to media/'
        }
    })
    $script:Window.FindName('ListVideos').Add_SelectionChanged({
        param($s,$e)
        if ($script:SuppressEvents) { return }
        $sel = $s.SelectedItem
        if ($sel) {
            $script:Window.FindName('RadVideoFixed').IsChecked = $true
            $script:Window.FindName('TxtSelectedVideo').Text = [string]$sel
            if (Test-Path -LiteralPath ([string]$sel)) {
                $fi = Get-Item -LiteralPath ([string]$sel)
                $script:Window.FindName('TxtVideoInfo').Text = ('{0:N1} MB  |  {1}' -f ($fi.Length/1MB), $fi.Extension)
            }
        }
    })
    $script:Window.FindName('BtnPreviewVideo').Add_Click({
        $sel = $script:Window.FindName('ListVideos').SelectedItem
        if (-not $sel) { $sel = $script:Config.video }
        if (-not $sel) { Show-Toast 'Select a video first' '#FFFFB020'; return }
        Invoke-TestAlarm -PreviewOnly -Video ([string]$sel)
    })
    $script:Window.FindName('BtnTestVideo').Add_Click({
        $sel = $script:Window.FindName('ListVideos').SelectedItem
        if (-not $sel -and $script:Config.video) { $sel = $script:Config.video }
        if ($sel) { Invoke-TestAlarm -Video ([string]$sel) }
        else { Invoke-TestAlarm }
    })
    $script:Window.FindName('BtnRemoveVideo').Add_Click({
        $sel = [string]$script:Window.FindName('ListVideos').SelectedItem
        if (-not $sel) { return }
        $media = Join-Path $script:AppRoot 'media'
        if (-not $sel.StartsWith($media, [StringComparison]::OrdinalIgnoreCase)) {
            Show-Toast 'Only videos inside media/ can be removed.' '#FFFFB020'
            return
        }
        $r = [System.Windows.MessageBox]::Show("Remove $(Split-Path $sel -Leaf) from media/?", 'Remove video', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
        Remove-Item -LiteralPath $sel -Force
        if ($script:Config.video -eq $sel) { $script:Config.video = ''; $script:Config.videoMode = 'random' }
        Save-UiConfig -Silent
        Refresh-VideoList
        Show-Toast 'Video removed'
    })
    $script:Window.FindName('BtnSaveVideo').Add_Click({ Save-VideoFromUi })

    $script:Window.FindName('BtnLogRefresh').Add_Click({ Refresh-Logs })
    $script:Window.FindName('BtnLogClear').Add_Click({
        $script:Window.FindName('GridLogs').ItemsSource = $null
        Show-Toast 'Log view cleared (file unchanged)'
    })
    $script:Window.FindName('BtnLogOpen').Add_Click({
        $logPath = Get-WakeupLogPath -Config $script:Config
        if (-not (Test-Path -LiteralPath $logPath)) {
            New-Item -ItemType File -Path $logPath -Force | Out-Null
        }
        Start-Process notepad.exe $logPath | Out-Null
    })

    $script:Window.FindName('BtnInstallGlobal').Add_Click({ Invoke-InstallHooks 'global' })
    $script:Window.FindName('BtnInstallProject').Add_Click({ Invoke-InstallHooks 'project' })
    $script:Window.FindName('BtnUninstallGlobal').Add_Click({ Invoke-UninstallHooks 'global' })
    $script:Window.FindName('BtnUninstallProject').Add_Click({ Invoke-UninstallHooks 'project' })
    $script:Window.FindName('BtnVerify').Add_Click({
        Refresh-Setup
        Refresh-Dashboard
        Show-Toast 'Verification complete'
    })

    $script:Window.FindName('BtnBrowseProject').Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Select project directory for Claude hooks'
        if ($dlg.ShowDialog() -eq 'OK') {
            $script:Window.FindName('TxtProjectPath').Text = $dlg.SelectedPath
            $script:Window.FindName('RadScopeProject').IsChecked = $true
        }
    })
    $script:Window.FindName('BtnSaveSettings').Add_Click({ Save-AppSettingsFromUi })

    $script:Window.FindName('BtnWizardBack').Add_Click({
        if ($script:WizardStep -gt 0) {
            $script:WizardStep--
            Show-WizardStep
        }
    })
    $script:Window.FindName('BtnWizardNext').Add_Click({
        switch ($script:WizardStep) {
            3 { Invoke-InstallHooks 'global' }
            4 {
                Invoke-TestAlarm
                Complete-Wizard
                return
            }
        }
        if ($script:WizardStep -lt 4) {
            $script:WizardStep++
            Show-WizardStep
        }
    })

    $script:Window.Add_Closing({
        param($s,$e)
        if ($script:ReallyExit) {
            if ($script:Tray) { $script:Tray.Visible = $false; $script:Tray.Dispose() }
            return
        }
        if ([bool]$script:Config.ui.minimizeToTray) {
            $e.Cancel = $true
            $script:Window.Hide()
            Show-Toast 'Minimized to tray - hooks still work'
        } else {
            $r = [System.Windows.MessageBox]::Show(
                "Minimize to tray or exit?`n`nYes = Tray`nNo = Exit`n`nClosing the manager does not disable Claude hooks.",
                'Claude Wakeup Alarm',
                'YesNoCancel',
                'Question'
            )
            if ($r -eq 'Yes') {
                $e.Cancel = $true
                $script:Window.Hide()
            } elseif ($r -eq 'Cancel') {
                $e.Cancel = $true
            } else {
                if ($script:Tray) { $script:Tray.Visible = $false; $script:Tray.Dispose() }
            }
        }
    })
}

# --- boot ---
$xamlPath = Join-Path $script:UiRoot 'MainWindow.xaml'
$themePath = (Join-Path $script:UiRoot 'assets\Theme.xaml').Replace('\', '/')
$xamlText = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$xamlText = $xamlText.Replace('Source="assets/Theme.xaml"', "Source=`"file:///$themePath`"")
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xamlText)
$script:Window = [System.Windows.Markup.XamlReader]::Load($reader)

$script:NavButtons = @(
    $script:Window.FindName('NavDashboard'),
    $script:Window.FindName('NavEvents'),
    $script:Window.FindName('NavAlarm'),
    $script:Window.FindName('NavVideos'),
    $script:Window.FindName('NavLogs'),
    $script:Window.FindName('NavSetup'),
    $script:Window.FindName('NavSettings')
)
$script:Pages = @{
    Dashboard = $script:Window.FindName('PageDashboard')
    Events    = $script:Window.FindName('PageEvents')
    Alarm     = $script:Window.FindName('PageAlarm')
    Videos    = $script:Window.FindName('PageVideos')
    Logs      = $script:Window.FindName('PageLogs')
    Setup     = $script:Window.FindName('PageSetup')
    Settings  = $script:Window.FindName('PageSettings')
}

$script:Config = Read-WakeupConfig
Bind-UiEvents
Initialize-Tray
Update-EventTogglesFromConfig
Update-AlarmControlsFromConfig
Update-SettingsPageFromConfig
Refresh-VideoList
Refresh-Dashboard
Refresh-Setup
Refresh-Logs

$script:PollTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:PollTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:PollTimer.Add_Tick({
    try {
        # reload lightweight fields in case external edits occurred
        Refresh-LiveStatus
    } catch {}
})
$script:PollTimer.Start()

if (-not [bool]$script:Config.ui.firstRunCompleted) {
    $script:WizardStep = 0
    Show-WizardStep
}

if ($SmokeClose) {
    Write-Output 'UI_LOADED_OK'
    $script:Window.Add_ContentRendered({
        $script:ReallyExit = $true
        $script:Window.Close()
    })
}

[void]$script:Window.ShowDialog()
if ($script:Tray) {
    $script:Tray.Visible = $false
    $script:Tray.Dispose()
}
