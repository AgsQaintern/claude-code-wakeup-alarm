# Claude Wakeup Alarm — macOS SwiftUI Manager

Native management UI for the bash alarm engine. Feature parity with the Windows WPF manager.

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`) or full Xcode
- `jq` (`brew install jq`)
- Optional: `ffmpeg` for ffplay (`brew install ffmpeg`)

## Launch

From the repo root:

```bash
chmod +x Launch-WakeupAlarm.command install.sh uninstall.sh wakeup.sh lib/*.sh tests/*.sh
./Launch-WakeupAlarm.command
```

Or build manually:

```bash
cd macos/WakeupAlarm
swift build -c release
WAKEUP_HOME="$(cd ../.. && pwd)" ./.build/release/WakeupAlarm
```

## Notes

- The manager only edits `config.json` and shells out to `install.sh` / `lib/play.sh` / `wakeup.sh`.
- Closing the window can hide to the menu bar; hooks keep working either way.
- Build and run on a Mac — this package cannot be compiled on Windows.
