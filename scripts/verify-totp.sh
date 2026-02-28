#!/bin/bash
# ai2fa — verify TOTP code from authenticator app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_config.sh
source "$SCRIPT_DIR/_config.sh"
_ai2fa_load_storage
# shellcheck source=_totp.sh
source "$SCRIPT_DIR/_totp.sh"

USER_CODE="${1:-}"

if [ -z "$USER_CODE" ]; then
  echo "FAILED:NO_INPUT"
  exit 1
fi

SECRET="$(storage_get "totp_secret")"
if [ -z "$SECRET" ]; then
  echo "FAILED:NO_TOTP_CONFIGURED"
  exit 1
fi

NORMALIZED_CODE=$(printf '%s' "$USER_CODE" | tr -d '[:space:]-')

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAILED:TOTP_UNAVAILABLE"
  exit 1
fi

set +e
MATCHED_COUNTER="$(_ai2fa_totp_match_counter "$SECRET" "$NORMALIZED_CODE" "$AI2FA_TOTP_WINDOW" 2>/dev/null)"
MATCH_RC=$?
set -e

case "$MATCH_RC" in
  0) ;;
  1)
    echo "FAILED:WRONG_TOTP"
    exit 1
    ;;
  2)
    echo "FAILED:INVALID_TOTP_FORMAT"
    exit 1
    ;;
  3)
    echo "FAILED:TOTP_SECRET_INVALID"
    exit 1
    ;;
  *)
    echo "FAILED:TOTP_UNAVAILABLE"
    exit 1
    ;;
esac

LAST_COUNTER="$(storage_get "totp_last_counter")"
if ! [[ "$LAST_COUNTER" =~ ^-?[0-9]+$ ]]; then
  LAST_COUNTER="-1"
fi

if [ "$MATCHED_COUNTER" -le "$LAST_COUNTER" ]; then
  echo "FAILED:REPLAY"
  exit 1
fi

storage_set "totp_last_counter" "$MATCHED_COUNTER"
echo "VERIFIED"
