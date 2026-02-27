#!/bin/bash
# ai2fa storage adapter — environment variables (fallback)
# Reads from ~/.ai2fa/secrets (chmod 600, key=value format)
# NOT as secure as Keychain or pass — use only as last resort

AI2FA_SECRETS_FILE="$AI2FA_CONFIG_DIR/secrets"

_ensure_secrets_file() {
  if [ ! -f "$AI2FA_SECRETS_FILE" ]; then
    touch "$AI2FA_SECRETS_FILE"
    chmod 600 "$AI2FA_SECRETS_FILE"
  fi
}

storage_get() {
  local key="$1"
  _ensure_secrets_file

  # Check env var first, then file
  local env_key="AI2FA_SECRET_${key}"
  local env_val="${!env_key:-}"
  if [ -n "$env_val" ]; then
    echo "$env_val"
    return
  fi

  # Check secrets file
  grep -E "^${key}=" "$AI2FA_SECRETS_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- || echo ""
}

storage_set() {
  local key="$1"
  local value="$2"
  _ensure_secrets_file

  # Remove existing line, append new
  local tmpfile
  tmpfile=$(mktemp)
  grep -v "^${key}=" "$AI2FA_SECRETS_FILE" > "$tmpfile" 2>/dev/null || true
  echo "${key}=${value}" >> "$tmpfile"
  mv "$tmpfile" "$AI2FA_SECRETS_FILE"
  chmod 600 "$AI2FA_SECRETS_FILE"
}

storage_delete() {
  local key="$1"
  _ensure_secrets_file
  local tmpfile
  tmpfile=$(mktemp)
  grep -v "^${key}=" "$AI2FA_SECRETS_FILE" > "$tmpfile" 2>/dev/null || true
  mv "$tmpfile" "$AI2FA_SECRETS_FILE"
  chmod 600 "$AI2FA_SECRETS_FILE"
}

storage_exists() {
  local key="$1"
  local env_key="AI2FA_SECRET_${key}"
  [ -n "${!env_key:-}" ] && return 0
  grep -qE "^${key}=" "$AI2FA_SECRETS_FILE" 2>/dev/null
}

storage_name() {
  echo "env/file ($AI2FA_SECRETS_FILE)"
}
