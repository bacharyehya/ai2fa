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

STORED_HASH=$(storage_get "challenge_phrase_hash")
STORED_SALT=$(storage_get "challenge_phrase_salt")

if [ -n "$STORED_HASH" ] && [ -n "$STORED_SALT" ]; then
  USER_HASH=$(_ai2fa_hash_phrase "$STORED_SALT" "$USER_PHRASE")
  if _ai2fa_secure_compare "$USER_HASH" "$STORED_HASH"; then
    echo "VERIFIED"
  else
    echo "FAILED:WRONG_PHRASE"
    exit 1
  fi
  exit 0
fi

STORED_PLAINTEXT=$(storage_get "challenge_phrase")
if [ -z "$STORED_PLAINTEXT" ]; then
  echo "FAILED:NO_PHRASE_CONFIGURED"
  exit 1
fi

if _ai2fa_secure_compare "$USER_PHRASE" "$STORED_PLAINTEXT"; then
  # Legacy auto-migration: replace plaintext phrase with salted hash.
  NEW_SALT=$(openssl rand -hex 16)
  NEW_HASH=$(_ai2fa_hash_phrase "$NEW_SALT" "$USER_PHRASE")
  storage_set "challenge_phrase_salt" "$NEW_SALT"
  storage_set "challenge_phrase_hash" "$NEW_HASH"
  storage_delete "challenge_phrase"
  echo "VERIFIED"
else
  echo "FAILED:WRONG_PHRASE"
  exit 1
fi
