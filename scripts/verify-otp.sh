#!/bin/bash
# ai2fa — Verify a user-provided code against stored hash
# The code is NEVER stored. Only hash comparison happens here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_config.sh
source "$SCRIPT_DIR/_config.sh"

USER_CODE="${1:-}"

if [ -z "$USER_CODE" ]; then
  echo "FAILED:NO_INPUT"
  exit 1
fi

STORE="/tmp/.ai2fa_$(id -u)"

if [ ! -f "$STORE" ]; then
  echo "FAILED:NO_CHALLENGE"
  exit 1
fi

# Check expiry
STORED_HASH=$(head -1 "$STORE")
STORED_TIME=$(tail -1 "$STORE")
CURRENT_TIME=$(date +%s)
ELAPSED=$(( CURRENT_TIME - STORED_TIME ))

if [ "$ELAPSED" -gt "$AI2FA_EXPIRY" ]; then
  rm -f "$STORE"
  echo "FAILED:EXPIRED"
  exit 1
fi

# Normalize input (uppercase hex), hash and compare
USER_HASH=$(echo -n "$(echo "$USER_CODE" | tr 'a-f' 'A-F')" | shasum -a 256 | cut -d' ' -f1)

if [ "$STORED_HASH" = "$USER_HASH" ]; then
  rm -f "$STORE"
  echo "VERIFIED"
else
  echo "FAILED:WRONG_CODE"
  exit 1
fi
