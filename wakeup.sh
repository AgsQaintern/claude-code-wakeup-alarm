#!/usr/bin/env bash
# Claude Code hook entrypoint (macOS).
#
# Returns in milliseconds and never exits non-zero so a broken config cannot
# break a Claude Code session.

set -uo pipefail

# shellcheck source=lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# Master switch from config.json
if [ "${WAKEUP_ENABLED:-1}" = "0" ]; then
  exit 0
fi

payload="$(cat 2>/dev/null)"

event="$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)"
ntype="$(printf '%s' "$payload" | jq -r '.notification_type // empty' 2>/dev/null)"

case "$event" in
  Stop)         key="stop"   ;;
  Notification) key="$ntype" ;;
  *)            key=""       ;;
esac

[ -n "$key" ] || exit 0

case " $WAKEUP_EVENTS " in
  *" $key "*) ;;
  *) exit 0 ;;
esac

if lock_held; then
  log "skip $key (an alarm is already armed)"
  exit 0
fi

( nohup "$WAKEUP_HOME/lib/play.sh" "$key" </dev/null >>"$WAKEUP_LOG" 2>&1 & ) >/dev/null 2>&1

exit 0
