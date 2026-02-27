#!/bin/bash
# ai2fa — Generate OTP, store hash, send via configured channel
# The actual code NEVER touches stdout or any file. Only the hash is stored.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_config.sh
source "$SCRIPT_DIR/_config.sh"
_ai2fa_load_storage
_ai2fa_load_channel

# Generate code (configurable length, default 3 bytes = 6 hex chars)
CODE=$(openssl rand -hex "$AI2FA_CODE_LENGTH" | tr 'a-f' 'A-F')

# Hash it — only the hash is stored locally
HASH=$(echo -n "$CODE" | shasum -a 256 | cut -d' ' -f1)
TIMESTAMP=$(date +%s)

# Store hash + timestamp in temp file (code expires per config)
STORE="/tmp/.ai2fa_$(id -u)"
echo "$HASH" > "$STORE"
echo "$TIMESTAMP" >> "$STORE"
chmod 600 "$STORE"

# Send via configured channel
if channel_send "🔐 ai2fa: ${CODE}"; then
  echo "SENT"
else
  rm -f "$STORE"
  exit 1
fi
