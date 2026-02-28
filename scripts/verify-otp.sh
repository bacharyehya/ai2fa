#!/bin/bash
# ai2fa — Verify a user-provided code against stored challenge digest
# The code is NEVER stored. Only keyed digest comparison happens here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_config.sh
source "$SCRIPT_DIR/_config.sh"
_ai2fa_load_storage

USER_CODE="${1:-}"

case "$AI2FA_FAIL_ACTION" in
  none|terminate_parent) ;;
  *) AI2FA_FAIL_ACTION="none" ;;
esac

_alert_failed_verify() {
  local reason="$1"

  if [ -z "$AI2FA_CHANNEL" ]; then
    return
  fi

  local channel_adapter="$SCRIPT_DIR/../channels/${AI2FA_CHANNEL}.sh"
  if [ ! -f "$channel_adapter" ]; then
    return
  fi

  # shellcheck source=/dev/null
  source "$channel_adapter"

  local host_name
  host_name=$(hostname 2>/dev/null || echo "unknown-host")
  local user_name
  user_name=$(id -un 2>/dev/null || echo "unknown-user")
  local when_utc
  when_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  channel_send "⚠️ ai2fa verify failed (${reason}) on ${host_name} as ${user_name} at ${when_utc}." >/dev/null 2>&1 || true
}

_terminate_parent_session() {
  local parent_pid="${PPID:-}"
  if ! [[ "$parent_pid" =~ ^[0-9]+$ ]] || [ "$parent_pid" -le 1 ]; then
    return
  fi

  kill -TERM "$parent_pid" 2>/dev/null || true
}

_fail_verify() {
  local reason="$1"
  local should_alert="${2:-true}"
  local should_terminate="${3:-true}"

  if [ "$should_alert" = "true" ] && [ "$AI2FA_FAIL_ACTION" = "terminate_parent" ]; then
    _alert_failed_verify "$reason"
  fi

  echo "FAILED:${reason}"

  if [ "$should_terminate" = "true" ] && [ "$AI2FA_FAIL_ACTION" = "terminate_parent" ]; then
    _terminate_parent_session
  fi

  exit 1
}

if [ -z "$USER_CODE" ]; then
  _fail_verify "NO_INPUT" "false" "false"
fi

if [ ! -f "$AI2FA_CHALLENGE_FILE" ]; then
  _fail_verify "NO_CHALLENGE"
fi

# Parse challenge state
STORED_MAC=$(sed -n 's/^MAC=//p' "$AI2FA_CHALLENGE_FILE" | head -1)
STORED_TIME=$(sed -n 's/^TIMESTAMP=//p' "$AI2FA_CHALLENGE_FILE" | head -1)
ATTEMPTS=$(sed -n 's/^ATTEMPTS=//p' "$AI2FA_CHALLENGE_FILE" | head -1)

if [ -z "$STORED_MAC" ] || [ -z "$STORED_TIME" ]; then
  rm -f "$AI2FA_CHALLENGE_FILE"
  _fail_verify "CORRUPT_CHALLENGE"
fi

[ -z "$ATTEMPTS" ] && ATTEMPTS=0

if ! [[ "$STORED_TIME" =~ ^[0-9]+$ ]] || ! [[ "$ATTEMPTS" =~ ^[0-9]+$ ]] || ! [[ "$AI2FA_EXPIRY" =~ ^[0-9]+$ ]] || ! [[ "$AI2FA_MAX_ATTEMPTS" =~ ^[0-9]+$ ]]; then
  rm -f "$AI2FA_CHALLENGE_FILE"
  _fail_verify "CORRUPT_CHALLENGE"
fi

# Check expiry
CURRENT_TIME=$(date +%s)
ELAPSED=$(( CURRENT_TIME - STORED_TIME ))

if [ "$ELAPSED" -gt "$AI2FA_EXPIRY" ]; then
  rm -f "$AI2FA_CHALLENGE_FILE"
  _fail_verify "EXPIRED"
fi

if [ "$ATTEMPTS" -ge "$AI2FA_MAX_ATTEMPTS" ]; then
  rm -f "$AI2FA_CHALLENGE_FILE"
  _fail_verify "LOCKED"
fi

# Normalize common formatting noise and compare keyed digests.
HMAC_KEY=$(storage_get "otp_hmac_key")
if [ -z "$HMAC_KEY" ] || ! [[ "$HMAC_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
  rm -f "$AI2FA_CHALLENGE_FILE"
  _fail_verify "KEY_MISSING"
fi

NORMALIZED_CODE=$(printf '%s' "$USER_CODE" | tr -d '[:space:]-' | tr '[:lower:]' '[:upper:]')
if [ -z "$NORMALIZED_CODE" ]; then
  _fail_verify "NO_INPUT" "false" "false"
fi
USER_MAC=$(printf '%s' "$NORMALIZED_CODE" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$HMAC_KEY" | awk '{print $NF}')

if [ "$STORED_MAC" = "$USER_MAC" ]; then
  rm -f "$AI2FA_CHALLENGE_FILE"
  echo "VERIFIED"
else
  ATTEMPTS=$((ATTEMPTS + 1))

  if [ "$ATTEMPTS" -ge "$AI2FA_MAX_ATTEMPTS" ]; then
    rm -f "$AI2FA_CHALLENGE_FILE"
    _fail_verify "LOCKED"
  fi

  _ai2fa_ensure_config_dir
  STATE_TMP=$(mktemp "$AI2FA_CONFIG_DIR/challenge.XXXXXX")
  cat > "$STATE_TMP" <<EOF
MAC=$STORED_MAC
TIMESTAMP=$STORED_TIME
ATTEMPTS=$ATTEMPTS
EOF
  chmod 600 "$STATE_TMP"
  mv "$STATE_TMP" "$AI2FA_CHALLENGE_FILE"

  _fail_verify "WRONG_CODE"
fi
