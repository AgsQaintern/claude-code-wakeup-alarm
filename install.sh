#!/usr/bin/env bash
# Install the wake-up hooks into Claude Code settings.json.
#
#   ./install.sh                         # global
#   ./install.sh --project               # this repo
#   ./install.sh --project /path/to/repo # specific project

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$ROOT/wakeup.sh"
PROJECT_PATH=""

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

if [ "${1:-}" = "--project" ]; then
  PROJECT_PATH="${2:-$ROOT}"
  SETTINGS="$PROJECT_PATH/.claude/settings.json"
  SCOPE="project: $PROJECT_PATH"
elif [ "${1:-}" = "--global" ] || [ -z "${1:-}" ]; then
  SETTINGS="$HOME/.claude/settings.json"
  SCOPE="every Claude Code session"
else
  echo "usage: ./install.sh [--project [path]]" >&2
  exit 1
fi

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"

if ! jq empty "$SETTINGS" 2>/dev/null; then
  echo "error: $SETTINGS is not valid JSON — fix it before installing" >&2
  exit 1
fi

BACKUP="$SETTINGS.bak.$(date +%s)"
cp "$SETTINGS" "$BACKUP"

TMP="$(mktemp)"
jq --arg cmd "$HOOK" '
  def strip:
    map(.hooks |= map(select((.command // "") | test("wakeup\\.sh") | not)))
    | map(select((.hooks | length) > 0));

  def entry: { matcher: "*", hooks: [ { type: "command", command: $cmd, timeout: 5 } ] };

  .hooks //= {}
  | .hooks.Notification = ((.hooks.Notification // []) | strip) + [entry]
  | .hooks.Stop         = ((.hooks.Stop         // []) | strip) + [entry]
' "$SETTINGS" >"$TMP"

jq empty "$TMP" 2>/dev/null || { echo "error: refusing to write invalid JSON" >&2; rm -f "$TMP"; exit 1; }
mv "$TMP" "$SETTINGS"

# Update config.json ui.scope / ui.projectPath
CFG="$ROOT/config.json"
if [ -f "$CFG" ] && command -v jq >/dev/null 2>&1; then
  CTMP="$(mktemp)"
  if [ -n "$PROJECT_PATH" ]; then
    jq --arg p "$PROJECT_PATH" '
      .ui //= {}
      | .ui.scope = "project"
      | .ui.projectPath = $p
    ' "$CFG" >"$CTMP" && mv "$CTMP" "$CFG"
  else
    jq '
      .ui //= {}
      | .ui.scope = "global"
    ' "$CFG" >"$CTMP" && mv "$CTMP" "$CFG"
  fi
fi

echo "installed → $SETTINGS  (active for: $SCOPE)"
echo "backup    → $BACKUP"
echo
jq '.hooks' "$SETTINGS"
echo
echo "Hooks load when a session starts, so restart Claude Code to arm it."
echo "Log: ${WAKEUP_LOG:-$HOME/.claude/wakeup.log}"
