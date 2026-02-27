#!/bin/bash
# ai2fa — Verify challenge phrase against stored secret
# The phrase is NEVER printed. Only VERIFIED/FAILED.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_config.sh
source "$SCRIPT_DIR/_config.sh"
_ai2fa_load_storage

USER_PHRASE="${1:-}"

if [ -z "$USER_PHRASE" ]; then
  echo "FAILED:NO_INPUT"
  exit 1
fi

STORED=$(storage_get "challenge_phrase")

if [ -z "$STORED" ]; then
  echo "FAILED:NO_PHRASE_CONFIGURED"
  exit 1
fi

if [ "$USER_PHRASE" = "$STORED" ]; then
  echo "VERIFIED"
else
  echo "FAILED:WRONG_PHRASE"
  exit 1
fi
