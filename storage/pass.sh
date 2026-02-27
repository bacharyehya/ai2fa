#!/bin/bash
# ai2fa storage adapter — pass (password-store, GPG-encrypted)
# https://www.passwordstore.org/

storage_get() {
  local key="$1"
  pass show "ai2fa/${key}" 2>/dev/null || echo ""
}

storage_set() {
  local key="$1"
  local value="$2"
  echo "$value" | pass insert -f "ai2fa/${key}" 2>/dev/null
}

storage_delete() {
  local key="$1"
  pass rm -f "ai2fa/${key}" 2>/dev/null || true
}

storage_exists() {
  local key="$1"
  pass show "ai2fa/${key}" &>/dev/null
}

storage_name() {
  echo "pass (GPG)"
}
