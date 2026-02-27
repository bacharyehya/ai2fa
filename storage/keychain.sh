#!/bin/bash
# ai2fa storage adapter — macOS Keychain
# Uses `security` command to store/retrieve secrets

storage_get() {
  local key="$1"
  security find-generic-password -s "ai2fa_${key}" -a "ai2fa" -w 2>/dev/null || echo ""
}

storage_set() {
  local key="$1"
  local value="$2"
  # Delete existing entry silently, then add
  security delete-generic-password -s "ai2fa_${key}" -a "ai2fa" 2>/dev/null || true
  security add-generic-password -s "ai2fa_${key}" -a "ai2fa" -w "$value"
}

storage_delete() {
  local key="$1"
  security delete-generic-password -s "ai2fa_${key}" -a "ai2fa" 2>/dev/null || true
}

storage_exists() {
  local key="$1"
  security find-generic-password -s "ai2fa_${key}" -a "ai2fa" -w &>/dev/null
}

storage_name() {
  echo "macOS Keychain"
}
