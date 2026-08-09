#!/usr/bin/env bash
# Remove the wake-up hooks. Leaves every other setting untouched.
#
#   ./uninstall.sh
#   ./uninstall.sh --project
#   ./uninstall.sh --project /path/to/repo

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--project" ]; then
  PROJECT_PATH="${2:-$ROOT}"
  SETTINGS="$PROJECT_PATH/.claude/settings.json"
else
  SETTINGS="$HOME/.claude/settings.json"
fi

if [ ! -f "$SETTINGS" ]; then
  echo "nothing to do: $SETTINGS does not exist"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

BACKUP="$SETTINGS.bak.$(date +%s)"
cp "$SETTINGS" "$BACKUP"

TMP="$(mktemp)"
jq '
  def strip:
    map(.hooks |= map(select((.command // "") | test("wakeup\\.sh") | not)))
    | map(select((.hooks | length) > 0));

  if .hooks then
    .hooks |= with_entries(.value |= strip)
    | .hooks |= with_entries(select((.value | length) > 0))
    | if (.hooks | length) == 0 then del(.hooks) else . end
  else . end
' "$SETTINGS" >"$TMP"

jq empty "$TMP" 2>/dev/null || { echo "error: refusing to write invalid JSON" >&2; rm -f "$TMP"; exit 1; }
mv "$TMP" "$SETTINGS"

echo "removed from → $SETTINGS"
echo "backup       → $BACKUP"
