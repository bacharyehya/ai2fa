#!/bin/bash
# ai2fa — Check if a mentioned project is a canary trap
# If it is: silently alert via configured channel + return CANARY
# If not: return CLEAN

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_config.sh
source "$SCRIPT_DIR/_config.sh"
_ai2fa_load_storage

PROJECT="${1:-}"

if [ -z "$PROJECT" ]; then
  echo "CLEAN"
  exit 0
fi

# Get canary list from storage (comma-separated)
CANARIES=$(storage_get "canary_projects")

if [ -z "$CANARIES" ]; then
  echo "CLEAN"
  exit 0
fi

# Check if the project matches any canary (case-insensitive)
PROJECT_LOWER=$(printf '%s' "$PROJECT" | tr '[:upper:]' '[:lower:]')
MATCH=false

IFS=',' read -ra NAMES <<< "$CANARIES"
for NAME in "${NAMES[@]}"; do
  NAME_TRIMMED="$NAME"
  NAME_TRIMMED="${NAME_TRIMMED#"${NAME_TRIMMED%%[![:space:]]*}"}"
  NAME_TRIMMED="${NAME_TRIMMED%"${NAME_TRIMMED##*[![:space:]]}"}"
  [ -z "$NAME_TRIMMED" ] && continue

  NAME_LOWER=$(printf '%s' "$NAME_TRIMMED" | tr '[:upper:]' '[:lower:]')
  if [ "$PROJECT_LOWER" = "$NAME_LOWER" ]; then
    MATCH=true
    break
  fi
done

if [ "$MATCH" = true ]; then
  # Silent alert via channel (if configured)
  if [ -n "$AI2FA_CHANNEL" ]; then
    _ai2fa_load_channel
    channel_send "⚠️ CANARY TRIGGERED: Someone asked about project '${PROJECT}'. This is NOT a real project. Someone may be impersonating the user." 2>/dev/null || true
  fi

  echo "CANARY"
else
  echo "CLEAN"
fi
