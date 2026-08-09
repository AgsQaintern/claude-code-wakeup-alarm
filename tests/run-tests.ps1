# Dry-run logic suite for the Windows wakeup engine.
# Safe anytime - fakes idle time, plays nothing.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Common.ps1')

$failed = 0
$passed = 0

function Assert-True($cond, $name) {
    if ($cond) {
        Write-Host "  PASS  $name" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  FAIL  $name" -ForegroundColor Red
        $script:failed++
    }
}

function Invoke-Hook {
    param([string]$Fixture, [hashtable]$EnvExtra = @{})
    $env:WAKEUP_DRY_RUN = '1'
    $env:WAKEUP_HOME = $root
    foreach ($k in $EnvExtra.Keys) { Set-Item -Path "env:$k" -Value $EnvExtra[$k] }
    $fixturePath = Join-Path $root "tests\fixtures\$Fixture"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $root 'wakeup.ps1')`""
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    foreach ($key in [System.Environment]::GetEnvironmentVariables('Process').Keys) {
        # inherit
    }
    $p = [System.Diagnostics.Process]::Start($psi)
    $json = Get-Content -LiteralPath $fixturePath -Raw
    $p.StandardInput.Write($json)
    $p.StandardInput.Close()
    if (-not $p.WaitForExit(15000)) {
        $p.Kill()
        throw "hook timed out for $Fixture"
    }
    Start-Sleep -Milliseconds 800
    return $p.ExitCode
}

function Get-TestLogTail([string]$log, [int]$n = 20) {
    if (-not (Test-Path $log)) { return '' }
    return ((Get-Content $log -Tail $n) -join "`n")
}

Write-Host '=== wakeup dry-run tests ==='
$testRoot = Join-Path $env:TEMP ("wakeup-tests-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

# Isolate config/log/lock
$cfg = Read-WakeupConfig
$cfg.enabled = $true
$cfg.delaySecs = 0
$cfg.idleSecs = 10
$cfg.events = @('permission_prompt','idle_prompt','agent_needs_input','agent_completed','stop')
$testConfig = Join-Path $testRoot 'config.json'
$env:WAKEUP_HOME = $root
# write temp config into real config backup/restore
$realConfig = Get-WakeupConfigPath
$cfgBackup = "$realConfig.testbak"
Copy-Item $realConfig $cfgBackup -Force -ErrorAction SilentlyContinue

try {
    Write-WakeupConfig -Config $cfg -Path $realConfig

    # 1. Away -> PLAY
    $log1 = Join-Path $testRoot '1.log'
    $lock1 = Join-Path $testRoot '1.lock'
    Remove-Item $log1 -ErrorAction SilentlyContinue
    $env:WAKEUP_LOG = $log1
    $env:WAKEUP_LOCK = $lock1
    $env:WAKEUP_IDLE_OVERRIDE = '60'
    $null = Invoke-Hook 'permission_prompt.json'
    Start-Sleep -Seconds 2
    $t = Get-TestLogTail $log1
    Assert-True ($t -match 'PLAY') 'away (idle 60) plays'

    # 2. At desk - skipped
    $log2 = Join-Path $testRoot '2.log'
    $lock2 = Join-Path $testRoot '2.lock'
    $env:WAKEUP_LOG = $log2
    $env:WAKEUP_LOCK = $lock2
    $env:WAKEUP_IDLE_OVERRIDE = '2'
    $null = Invoke-Hook 'permission_prompt.json'
    Start-Sleep -Seconds 2
    $t = Get-TestLogTail $log2
    Assert-True ($t -match 'skipped:') 'at desk (idle 2) skipped'

    # 3. Stop event
    $log3 = Join-Path $testRoot '3.log'
    $lock3 = Join-Path $testRoot '3.lock'
    $env:WAKEUP_LOG = $log3
    $env:WAKEUP_LOCK = $lock3
    $env:WAKEUP_IDLE_OVERRIDE = '60'
    $null = Invoke-Hook 'stop.json'
    Start-Sleep -Seconds 2
    $t = Get-TestLogTail $log3
    Assert-True ($t -match 'trigger=stop' -or $t -match 'armed by stop') 'Stop event arms alarm'

    # 4. auth_success ignored
    $log4 = Join-Path $testRoot '4.log'
    $lock4 = Join-Path $testRoot '4.lock'
    $env:WAKEUP_LOG = $log4
    $env:WAKEUP_LOCK = $lock4
    $env:WAKEUP_IDLE_OVERRIDE = '60'
    $null = Invoke-Hook 'auth_success.json'
    Start-Sleep -Seconds 1
    $exists = Test-Path $log4
    $content = if ($exists) { Get-Content $log4 -Raw } else { '' }
    Assert-True ([string]::IsNullOrWhiteSpace($content) -or $content -notmatch 'PLAY') 'auth_success ignored'

    # 5. Malformed JSON exits 0
    $log5 = Join-Path $testRoot '5.log'
    $env:WAKEUP_LOG = $log5
    $env:WAKEUP_LOCK = (Join-Path $testRoot '5.lock')
    $code = Invoke-Hook 'malformed.json'
    Assert-True ($code -eq 0) 'malformed JSON exit 0'

    # 6. empty JSON exits 0
    $code = Invoke-Hook 'empty.json'
    Assert-True ($code -eq 0) 'empty JSON exit 0'

    # 7. resolve video finds media
    $v = Resolve-WakeupVideo -Config $cfg
    Assert-True ($null -ne $v -and (Test-Path $v)) 'resolve_video finds media clip'

    # 8. FFplay detection does not throw
    $null = Test-WakeupFFplay
    Assert-True $true 'ffplay detection runs'

    # 9. Config roundtrip
    $cfg2 = Read-WakeupConfig
    $cfg2.delaySecs = 11
    Write-WakeupConfig -Config $cfg2
    $cfg3 = Read-WakeupConfig
    Assert-True ([int]$cfg3.delaySecs -eq 11) 'config atomic write roundtrip'
}
finally {
    if (Test-Path $cfgBackup) {
        Move-Item $cfgBackup $realConfig -Force
    }
    Remove-Item Env:WAKEUP_DRY_RUN -ErrorAction SilentlyContinue
    Remove-Item Env:WAKEUP_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:WAKEUP_LOCK -ErrorAction SilentlyContinue
    Remove-Item Env:WAKEUP_IDLE_OVERRIDE -ErrorAction SilentlyContinue
    Remove-Item Env:WAKEUP_HOME -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "Passed: $passed  Failed: $failed"
if ($failed -gt 0) { exit 1 } else { exit 0 }
