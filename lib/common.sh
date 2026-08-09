#!/usr/bin/env bash
# Shared settings and helpers. Sourced by wakeup.sh and lib/play.sh.

# shellcheck source=config.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

log() {
  mkdir -p "$(dirname "$WAKEUP_LOG")" 2>/dev/null
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$WAKEUP_LOG" 2>/dev/null
  return 0
}

write_status() {
  local state="$1" trigger="${2:-}" video="${3:-}" idle="${4:--1}" message="${5:-}"
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S")"
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg state "$state" \
      --arg trigger "$trigger" \
      --arg video "$video" \
      --arg message "$message" \
      --arg updatedAt "$now" \
      --argjson idleSecs "$idle" \
      --argjson pid "$$" \
      '{state:$state,trigger:$trigger,video:$video,idleSecs:$idleSecs,message:$message,pid:$pid,updatedAt:$updatedAt}' \
      >"$WAKEUP_STATUS" 2>/dev/null || true
  else
    printf '{"state":"%s","trigger":"%s","video":"","idleSecs":%s,"message":"%s","pid":%s,"updatedAt":"%s"}\n' \
      "$state" "$trigger" "$idle" "$message" "$$" "$now" >"$WAKEUP_STATUS" 2>/dev/null || true
  fi
}

clear_status() {
  write_status "idle" "" "" "$(idle_secs)" ""
}

# Seconds since the last keyboard or mouse input.
idle_secs() {
  if [ -n "${WAKEUP_IDLE_OVERRIDE_FILE:-}" ] && [ -r "${WAKEUP_IDLE_OVERRIDE_FILE}" ]; then
    printf '%s\n' "$(cat "$WAKEUP_IDLE_OVERRIDE_FILE" 2>/dev/null || echo 0)"
    return 0
  fi
  if [ -n "${WAKEUP_IDLE_OVERRIDE:-}" ]; then
    printf '%s\n' "$WAKEUP_IDLE_OVERRIDE"
    return 0
  fi
  local n
  n="$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')"
  case "$n" in
    ''|*[!0-9]*)
      printf '999\n' ;;
    *) printf '%s\n' "$n" ;;
  esac
}

# Fixed WAKEUP_VIDEO, else random clip from media/.
resolve_video() {
  if [ -n "$WAKEUP_VIDEO" ]; then
    printf '%s\n' "$WAKEUP_VIDEO"
    return 0
  fi
  local -a clips=()
  local f
  for f in "$WAKEUP_HOME"/media/*.mp4 "$WAKEUP_HOME"/media/*.mov "$WAKEUP_HOME"/media/*.mkv "$WAKEUP_HOME"/media/*.webm; do
    [ -f "$f" ] && clips+=("$f")
  done
  [ ${#clips[@]} -gt 0 ] || return 0
  printf '%s\n' "${clips[RANDOM % ${#clips[@]}]}"
}

lock_held() {
  [ -d "$WAKEUP_LOCK" ] || return 1
  local pid
  pid="$(cat "$WAKEUP_LOCK/pid" 2>/dev/null)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}
