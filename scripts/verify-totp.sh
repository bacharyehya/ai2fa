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

MATCHED_COUNTER="$(_ai2fa_totp_match_counter "$SECRET" "$USER_CODE" "$AI2FA_TOTP_WINDOW" 2>/dev/null || true)"
if [ -z "$MATCHED_COUNTER" ]; then
  echo "FAILED:WRONG_TOTP"
  exit 1
fi

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
