# Claude Code Wakeup Alarm

You give Claude Code a long task. You pick up your phone. Twenty minutes later you look
back and it has been sitting on a permission prompt the whole time.

This fixes that. When Claude Code needs you, it plays a video fullscreen — with sound —
and stops the moment you touch the keyboard or mouse.

```
Claude needs permission  ->  wait 10s  ->  still away?  ->  VIDEO
                                      \->  you're typing? -> stays quiet
```

**Windows:** PowerShell engine + WPF manager  
**macOS:** bash engine + SwiftUI manager  

Both platforms share one [`config.json`](config.json) schema. Closing the manager does
**not** disable hooks.

## Quick start

### Windows

```powershell
cd "path\to\claude-code-wakeup-alarm"
.\Launch-WakeupAlarm.ps1
```

### macOS

```bash
cd /path/to/claude-code-wakeup-alarm
chmod +x Launch-WakeupAlarm.command install.sh uninstall.sh wakeup.sh lib/*.sh tests/*.sh
./Launch-WakeupAlarm.command
```

Needs `jq` (`brew install jq`). Optional: `ffmpeg` for ffplay; otherwise QuickTime is used.

On first launch, a short setup wizard walks you through detect → video → events → install → test.

## Architecture

```
Manager UI  <-->  config.json
                     ^
Cursor -> Claude Code -> hooks -> wakeup.(ps1|sh)
                                  |
                               lib/play.(ps1|sh)
                                  |
                        idle API + ffplay / OS player
```

| Piece | Windows | macOS |
|---|---|---|
| Hook | `wakeup.ps1` | `wakeup.sh` |
| Worker | `lib/Play.ps1` | `lib/play.sh` |
| Config load | `lib/Config.ps1` | `lib/config.sh` (jq) |
| Idle | `GetLastInputInfo` | `ioreg` HIDIdleTime |
| Fallback player | WPF MediaElement | QuickTime |
| Manager | WPF (`ui/`) | SwiftUI (`macos/WakeupAlarm/`) |
| Autostart | HKCU Run | Login item / LaunchAgent |

## Install hooks (CLI)

### Windows

```powershell
.\install.ps1              # global: ~/.claude/settings.json
.\install.ps1 -Project     # this repo only
.\uninstall.ps1
```

### macOS

```bash
./install.sh               # global
./install.sh --project     # this repo
./uninstall.sh
```

Restart Claude Code after installing (hooks load at session start).

## Configuration

Everything lives in [`config.json`](config.json). The UI and engine share this file only.

| Field | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Master alarm switch |
| `delaySecs` | `10` | Grace period after Claude asks |
| `idleSecs` | `15` | Only fire if idle at least this long |
| `returnSecs` | `2` | Idle below this = you are back, stop |
| `maxSecs` | `120` | Hard playback cap |
| `loop` | `false` | Replay until return |
| `events` | all five | Which moments arm the alarm |
| `video` / `videoMode` | random | Fixed path or random from `media/` |
| `player` | `auto` | `auto` / `ffplay` / `windows` / `quicktime` |
| `volume` | `null` | macOS: force 0–100 then restore; Windows: ignored |
| `logPath` | `~/.claude/wakeup.log` | Decision log |
| `ui.startAtLogin` | `false` | Start manager at login |
| `ui.minimizeToTray` | `true` | Close → tray / menu bar |
| `ui.scope` | `global` | Hook install scope |

Saves use atomic write (temp + replace).

## Manager features

Dashboard, Events, Alarm, Videos, Logs, Setup, Settings, first-run wizard, tray/menu bar,
test alarm, and simulate fixtures through the real hook pipeline. See platform READMEs:

- Windows details: this file historically covered WPF; behavior matches the in-app Setup page
- macOS build notes: [`macos/WakeupAlarm/README.md`](macos/WakeupAlarm/README.md)

## Tests

### Windows

```powershell
.\tests\run-tests.ps1
.\tests\live-test.ps1
.\tests\smoke-ui.ps1
```

### macOS

```bash
./tests/run-tests.sh
./tests/live-test.sh
./tests/live-test.sh --real
```

## Troubleshooting

**Nothing happens.** Check `~/.claude/wakeup.log` (or `%USERPROFILE%\.claude\wakeup.log`).
If empty, hooks are not installed or Claude Code was not restarted.

**Fires while I am working.** Raise `idleSecs`, or remove `stop` from `events`.

**No ffplay.** Leave `player` on `auto` — Windows uses MediaElement; macOS uses QuickTime.

**Manager vs hooks.** Closing the manager does not remove hooks. Use Setup → Uninstall
(or `uninstall.ps1` / `uninstall.sh`).

## License

MIT
