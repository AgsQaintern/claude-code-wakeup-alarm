#!/bin/bash
# Launch the Claude Wakeup Alarm macOS manager.
# Double-click in Finder, or run from Terminal.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export WAKEUP_HOME="$ROOT"
cd "$ROOT"

APP_DIR="$ROOT/macos/WakeupAlarm"

if ! command -v swift >/dev/null 2>&1; then
  osascript -e 'display dialog "Xcode Command Line Tools (swift) are required.\n\nInstall with: xcode-select --install" buttons {"OK"} default button 1'
  exit 1
fi

# Prefer an already-built binary if present
BIN=""
if [ -x "$APP_DIR/.build/release/WakeupAlarm" ]; then
  BIN="$APP_DIR/.build/release/WakeupAlarm"
elif [ -x "$APP_DIR/.build/debug/WakeupAlarm" ]; then
  BIN="$APP_DIR/.build/debug/WakeupAlarm"
fi

if [ -z "$BIN" ]; then
  echo "Building WakeupAlarm (first launch may take a minute)…"
  (cd "$APP_DIR" && swift build -c release)
  BIN="$APP_DIR/.build/release/WakeupAlarm"
fi

exec "$BIN"
