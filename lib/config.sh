#!/usr/bin/env bash
# Load shared config.json into WAKEUP_* env vars.
# Env vars already set win (test overrides). Missing jq / file falls back to defaults.

WAKEUP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WAKEUP_HOME

CONFIG_JSON="${WAKEUP_CONFIG:-$WAKEUP_HOME/config.json}"

_json_get() {
  local key="$1" default="$2"
  if ! command -v jq >/dev/null 2>&1 || [ ! -f "$CONFIG_JSON" ]; then
    printf '%s' "$default"
    return 0
  fi
  local v
  v="$(jq -r "$key" "$CONFIG_JSON" 2>/dev/null)" || v=""
  if [ -z "$v" ] || [ "$v" = "null" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$v"
  fi
}

_set_if_unset() {
  # usage: _set_if_unset VARNAME value
  local name="$1" val="$2"
  if [ -z "${!name+x}" ] || [ -z "${!name}" ]; then
    # only treat empty as unset for optional vars; for required use separate checks
    eval "$name=\"\$val\""
  fi
}

# Master switch
if [ -z "${WAKEUP_ENABLED+x}" ]; then
  _en="$(_json_get '.enabled' 'true')"
  case "$_en" in
    true|True|1) WAKEUP_ENABLED=1 ;;
    *) WAKEUP_ENABLED=0 ;;
  esac
fi
export WAKEUP_ENABLED

if [ -z "${WAKEUP_DELAY_SECS+x}" ]; then WAKEUP_DELAY_SECS="$(_json_get '.delaySecs' '10')"; fi
if [ -z "${WAKEUP_IDLE_SECS+x}" ]; then WAKEUP_IDLE_SECS="$(_json_get '.idleSecs' '15')"; fi
if [ -z "${WAKEUP_RETURN_SECS+x}" ]; then WAKEUP_RETURN_SECS="$(_json_get '.returnSecs' '2')"; fi
if [ -z "${WAKEUP_MAX_SECS+x}" ]; then WAKEUP_MAX_SECS="$(_json_get '.maxSecs' '120')"; fi

if [ -z "${WAKEUP_LOOP+x}" ]; then
  _loop="$(_json_get '.loop' 'false')"
  case "$_loop" in
    true|True|1) WAKEUP_LOOP=1 ;;
    *) WAKEUP_LOOP=0 ;;
  esac
fi

if [ -z "${WAKEUP_EVENTS+x}" ]; then
  if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_JSON" ]; then
    WAKEUP_EVENTS="$(jq -r '(.events // []) | join(" ")' "$CONFIG_JSON" 2>/dev/null || true)"
  fi
  if [ -z "${WAKEUP_EVENTS:-}" ]; then
    WAKEUP_EVENTS="permission_prompt idle_prompt agent_needs_input agent_completed stop"
  fi
fi

if [ -z "${WAKEUP_VIDEO+x}" ]; then
  _mode="$(_json_get '.videoMode' 'random')"
  _vid="$(_json_get '.video' '')"
  if [ "$_mode" = "fixed" ] && [ -n "$_vid" ] && [ "$_vid" != "null" ]; then
    WAKEUP_VIDEO="$_vid"
  else
    WAKEUP_VIDEO=""
  fi
fi

if [ -z "${WAKEUP_PLAYER+x}" ]; then
  WAKEUP_PLAYER="$(_json_get '.player' 'auto')"
fi
case "$WAKEUP_PLAYER" in
  windows) WAKEUP_PLAYER=auto ;;
esac
if [ "$WAKEUP_PLAYER" = "auto" ]; then
  if command -v ffplay >/dev/null 2>&1; then
    WAKEUP_PLAYER=ffplay
  else
    WAKEUP_PLAYER=quicktime
  fi
fi

if [ -z "${WAKEUP_VOLUME+x}" ]; then
  _vol="$(_json_get '.volume' '')"
  if [ "$_vol" = "null" ]; then _vol=""; fi
  WAKEUP_VOLUME="$_vol"
fi

if [ -z "${WAKEUP_LOG+x}" ]; then
  _lp="$(_json_get '.logPath' '')"
  if [ -n "$_lp" ] && [ "$_lp" != "null" ]; then
    WAKEUP_LOG="$_lp"
  else
    WAKEUP_LOG="$HOME/.claude/wakeup.log"
  fi
fi

if [ -z "${WAKEUP_LOCK+x}" ]; then
  WAKEUP_LOCK="${TMPDIR:-/tmp}/claude-wakeup.lock"
fi
if [ -z "${WAKEUP_STATUS+x}" ]; then
  WAKEUP_STATUS="${TMPDIR:-/tmp}/claude-wakeup.status.json"
fi

export WAKEUP_DELAY_SECS WAKEUP_IDLE_SECS WAKEUP_RETURN_SECS WAKEUP_MAX_SECS
export WAKEUP_LOOP WAKEUP_EVENTS WAKEUP_VIDEO WAKEUP_PLAYER WAKEUP_VOLUME
export WAKEUP_LOG WAKEUP_LOCK WAKEUP_STATUS
