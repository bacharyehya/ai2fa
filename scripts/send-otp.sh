#!/bin/bash
# ai2fa — Generate OTP, store keyed digest, send via configured channel
# The actual code NEVER touches stdout or local files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_config.sh
source "$SCRIPT_DIR/_config.sh"
_ai2fa_load_storage
_ai2fa_load_channel

if ! [[ "$AI2FA_CODE_LENGTH" =~ ^[0-9]+$ ]] || [ "$AI2FA_CODE_LENGTH" -lt 1 ]; then
  echo "ERROR: Invalid code_length '$AI2FA_CODE_LENGTH' in config" >&2
  exit 1
fi

# Generate code (configurable length, default 6 bytes = 12 hex chars)
CODE=$(openssl rand -hex "$AI2FA_CODE_LENGTH" | tr 'a-f' 'A-F')

# HMAC key is stored in the configured secret backend (not in challenge state).
HMAC_KEY=$(storage_get "otp_hmac_key")
if [ -z "$HMAC_KEY" ] || ! [[ "$HMAC_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
  HMAC_KEY=$(openssl rand -hex 32)
  storage_set "otp_hmac_key" "$HMAC_KEY"
fi

# Store a keyed digest, never the raw code.
MAC=$(printf '%s' "$CODE" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$HMAC_KEY" | awk '{print $NF}')
TIMESTAMP=$(date +%s)

# Store challenge state in user-owned directory (not /tmp).
_ai2fa_ensure_config_dir
STATE_TMP=$(mktemp "$AI2FA_CONFIG_DIR/challenge.XXXXXX")
cat > "$STATE_TMP" <<EOF
MAC=$MAC
TIMESTAMP=$TIMESTAMP
ATTEMPTS=0
EOF
chmod 600 "$STATE_TMP"
mv "$STATE_TMP" "$AI2FA_CHALLENGE_FILE"

# Send via configured channel
if channel_send "🔐 ai2fa: ${CODE}"; then
  echo "SENT"
else
  rm -f "$AI2FA_CHALLENGE_FILE"
  exit 1
fi
