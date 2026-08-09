# Claude Wakeup Alarm — team setup

Repo: https://github.com/AgsQaintern/claude-code-wakeup-alarm

Stops you from missing Claude Code permission prompts / waiting states. If Claude needs you and you have been away from the keyboard, it plays a fullscreen alarm video and stops when you touch mouse/keyboard again.

Closing the manager UI does **not** disable the alarm. Hooks run independently.

---

## Windows (quick)

```powershell
git clone https://github.com/AgsQaintern/claude-code-wakeup-alarm.git
cd claude-code-wakeup-alarm
.\Launch-WakeupAlarm.cmd
```

Or double-click `Launch-WakeupAlarm.cmd` (more reliable than double-clicking `.ps1`).

First launch wizard:

1. Detect Claude Code  
2. Choose video  
3. Choose events  
4. Install hooks  
5. Test Alarm  

Then restart Claude Code once so hooks load.

### Useful manager actions

- **TEST ALARM** — plays immediately (click video / press key to stop)  
- **Setup → Install Globally** — recommended for daily use  
- Dashboard toggle **ON/OFF** — master switch without uninstalling hooks  

### If video never plays while you are working

By design it stays quiet if you are at the keyboard (`idle < idleSecs`). Walk away for a few seconds after Claude prompts, or use **TEST ALARM** to verify playback.

Logs: `%USERPROFILE%\.claude\wakeup.log`

---

## macOS (quick)

```bash
git clone https://github.com/AgsQaintern/claude-code-wakeup-alarm.git
cd claude-code-wakeup-alarm
chmod +x Launch-WakeupAlarm.command install.sh uninstall.sh wakeup.sh lib/*.sh tests/*.sh
./Launch-WakeupAlarm.command
```

Needs `jq` (`brew install jq`). Optional: `ffmpeg` for ffplay (otherwise QuickTime).

See also: [`macos/WakeupAlarm/README.md`](macos/WakeupAlarm/README.md)

---

## CLI install (optional)

Windows:

```powershell
.\install.ps1              # global
.\install.ps1 -Project     # this repo only
.\uninstall.ps1
```

macOS:

```bash
./install.sh
./install.sh --project
./uninstall.sh
```

Restart Claude Code after install/uninstall.

---

## Notes

- One shared `config.json` for Windows + macOS  
- Do not delete unrelated Claude settings; install/uninstall only touch wakeup hooks  
- No Cursor extension required — works with Claude Code in Cursor/terminal  
