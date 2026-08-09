@echo off
REM Double-click this file to open Claude Wakeup Alarm
cd /d "%~dp0"
start "Claude Wakeup Alarm" powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%~dp0ui\WakeupAlarmUI.ps1"
