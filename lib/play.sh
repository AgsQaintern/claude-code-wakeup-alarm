#!/usr/bin/env bash
# Detached worker: wait out the grace period, check you're actually away, play the
# alarm, and cut it the moment you touch the keyboard.
#
# Usage: play.sh <trigger> [--immediate] [--force] [--video PATH] [--preview]

set -uo pipefail

# shellcheck source=common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

trigger="unknown"
IMMEDIATE=0
FORCE=0
VIDEO_OVERRIDE=""
PREVIEW=0

while [ $# -gt 0 ]; do
  case "$1" in
    --immediate) IMMEDIATE=1; shift ;;
    --force) FORCE=1; shift ;;
    --preview) PREVIEW=1; FORCE=1; IMMEDIATE=1; shift ;;
    --video) VIDEO_OVERRIDE="${2:-}"; shift 2 ;;
    -*)
      log "WARN unknown play.sh flag: $1"
      shift ;;
    *)
      if [ "$trigger" = "unknown" ]; then trigger="$1"; else VIDEO_OVERRIDE="$1"; fi
      shift ;;
  esac
done

# Env aliases used by the SwiftUI manager / tests
[ "${WAKEUP_IMMEDIATE:-0}" = "1" ] && IMMEDIATE=1
[ "${WAKEUP_FORCE_PLAY:-0}" = "1" ] && FORCE=1
[ -n "${WAKEUP_VIDEO_OVERRIDE:-}" ] && VIDEO_OVERRIDE="$WAKEUP_VIDEO_OVERRIDE"

PLAYER_PID=""
PREV_VOLUME=""

acquire_lock() {
  if mkdir "$WAKEUP_LOCK" 2>/dev/null; then
    echo $$ >"$WAKEUP_LOCK/pid"
    return 0
  fi
  local pid
  pid="$(cat "$WAKEUP_LOCK/pid" 2>/dev/null)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  rm -rf "$WAKEUP_LOCK" 2>/dev/null
  mkdir "$WAKEUP_LOCK" 2>/dev/null || return 1
  echo $$ >"$WAKEUP_LOCK/pid"
}

set_volume() {
  [ -n "$WAKEUP_VOLUME" ] || return 0
  PREV_VOLUME="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
  osascript -e "set volume output volume $WAKEUP_VOLUME" \
            -e 'set volume without output muted' >/dev/null 2>&1
}

restore_volume() {
  [ -n "$PREV_VOLUME" ] || return 0
  osascript -e "set volume output volume $PREV_VOLUME" >/dev/null 2>&1
}

qt_start() {
  osascript >/dev/null 2>&1 <<OSA
tell application "QuickTime Player"
  activate
  set d to open POSIX file "$1"
  tell d
    set looping to false
    present
    play
  end tell
end tell
OSA
}

qt_running() {
  local r
  r="$(osascript -e 'tell application "QuickTime Player" to if (count documents) > 0 then return (playing of front document) else return false' 2>/dev/null)"
  [ "$r" = "true" ]
}

qt_stop() {
  osascript -e 'tell application "QuickTime Player" to if (count documents) > 0 then close front document saving no' \
            -e 'tell application "QuickTime Player" to quit' >/dev/null 2>&1
}

start_player() {
  if [ "$WAKEUP_PLAYER" != "quicktime" ] && ! command -v ffplay >/dev/null 2>&1; then
    log "ffplay not installed — using QuickTime instead"
    WAKEUP_PLAYER="quicktime"
  fi
  if [ "$WAKEUP_PLAYER" = "quicktime" ]; then
    qt_start "$1"
  else
    ffplay -fs -autoexit -loglevel quiet "$1" >/dev/null 2>&1 &
    PLAYER_PID=$!
  fi
}

player_running() {
  if [ "$WAKEUP_PLAYER" = "quicktime" ]; then
    qt_running
  else
    [ -n "$PLAYER_PID" ] && kill -0 "$PLAYER_PID" 2>/dev/null
  fi
}

stop_player() {
  if [ "$WAKEUP_PLAYER" = "quicktime" ]; then
    qt_stop
  elif [ -n "$PLAYER_PID" ]; then
    kill "$PLAYER_PID" 2>/dev/null
    wait "$PLAYER_PID" 2>/dev/null
  fi
}

cleanup() {
  stop_player
  restore_volume
  clear_status
  rm -rf "$WAKEUP_LOCK" 2>/dev/null
}

acquire_lock || { log "skip $trigger (another alarm holds the lock)"; exit 0; }
trap cleanup EXIT INT TERM

write_status "armed" "$trigger" "" "$(idle_secs)" ""

delay="$WAKEUP_DELAY_SECS"
[ "$IMMEDIATE" = "1" ] && delay=0

if [ "$delay" -gt 0 ]; then
  log "armed by $trigger — waiting ${delay}s"
  sleep "$delay"
else
  log "armed by $trigger — immediate"
fi

idle="$(idle_secs)"
if [ "$FORCE" != "1" ] && [ "$PREVIEW" != "1" ] && [ "$idle" -lt "$WAKEUP_IDLE_SECS" ]; then
  log "skipped: you're here (idle ${idle}s < ${WAKEUP_IDLE_SECS}s)"
  exit 0
fi

video="$VIDEO_OVERRIDE"
if [ -z "$video" ]; then
  video="$(resolve_video)"
fi
if [ -z "$video" ] || [ ! -f "$video" ]; then
  log "WARN nothing to play (WAKEUP_VIDEO='$WAKEUP_VIDEO', no clips in media/?)"
  exit 0
fi

if [ "${WAKEUP_DRY_RUN:-0}" = "1" ]; then
  write_status "idle" "$trigger" "$video" "$idle" "dry-run"
  log "PLAY $video (dry run, trigger=$trigger, idle=${idle}s)"
  exit 0
fi

set_volume
write_status "playing" "$trigger" "$video" "$idle" ""
log "PLAY $video (trigger=$trigger, idle=${idle}s)"

deadline=$(( SECONDS + WAKEUP_MAX_SECS ))
while :; do
  start_player "$video"
  while player_running; do
    idle_now="$(idle_secs)"
    write_status "playing" "$trigger" "$video" "$idle_now" ""
    if [ "$idle_now" -lt "$WAKEUP_RETURN_SECS" ]; then
      log "you're back — stopping"
      exit 0
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      log "hit WAKEUP_MAX_SECS (${WAKEUP_MAX_SECS}s) — stopping"
      exit 0
    fi
    sleep 1
  done
  [ "$WAKEUP_LOOP" = "1" ] && [ "$SECONDS" -lt "$deadline" ] || break
done

log "played through"
