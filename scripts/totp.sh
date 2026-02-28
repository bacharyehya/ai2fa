#!/bin/bash
# ai2fa — TOTP management (Google Authenticator, 1Password, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_config.sh
source "$SCRIPT_DIR/_config.sh"
_ai2fa_load_storage
# shellcheck source=_totp.sh
source "$SCRIPT_DIR/_totp.sh"

usage() {
  cat <<'EOF'
ai2fa totp <subcommand>

Subcommands:
  setup [SECRET]    Generate (or set) TOTP secret and print otpauth URI
  verify <CODE>     Verify a 6-digit authenticator code
  disable           Remove TOTP secret and replay state
  status            Show TOTP configuration status
EOF
}

mask_secret() {
  local secret="$1"
  local len="${#secret}"
  if [ "$len" -le 8 ]; then
    printf '********'
    return
  fi
  printf '%s****%s' "${secret:0:4}" "${secret: -4}"
}

normalize_secret() {
  printf '%s' "$1" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'
}

validate_secret() {
  local secret="$1"
  # Validate using matcher with an impossible code.
  # Exit code 3 means secret format decode succeeded but code mismatch.
  set +e
  _ai2fa_totp_match_counter "$secret" "000000" "0" >/dev/null 2>&1
  local rc=$?
  set -e
  case "$rc" in
    0|1|3) return 0 ;;
    *) return 1 ;;
  esac
}

cmd_setup() {
  local secret="${1:-}"
  local account
  local uri

  if [ -z "$secret" ]; then
    secret="$(_ai2fa_totp_generate_secret)"
  fi
  secret="$(normalize_secret "$secret")"

  if ! validate_secret "$secret"; then
    _ai2fa_err "Invalid TOTP secret format"
    exit 1
  fi

  storage_set "totp_secret" "$secret"
  storage_set "totp_last_counter" "-1"

  account="$(id -un 2>/dev/null || echo user)@$(hostname 2>/dev/null || echo host)"
  uri="$(_ai2fa_totp_otpauth_uri "$secret" "$account" "ai2fa")"

  echo "TOTP configured."
  echo "Secret: $secret"
  echo "URI: $uri"
  if command -v qrencode >/dev/null 2>&1; then
    echo ""
    echo "Scan this QR code in your authenticator app:"
    qrencode -t ANSIUTF8 "$uri"
  fi
}

cmd_verify() {
  local code="${1:-}"
  if [ -z "$code" ]; then
    _ai2fa_err "Usage: ai2fa totp verify <CODE>"
    exit 1
  fi
  bash "$SCRIPT_DIR/verify-totp.sh" "$code"
}

cmd_disable() {
  storage_delete "totp_secret"
  storage_delete "totp_last_counter"
  _ai2fa_ok "TOTP disabled"
}

cmd_status() {
  local secret
  local mode
  secret="$(storage_get "totp_secret")"
  mode="${AI2FA_TOTP_MODE:-off}"
  if [ -n "$secret" ]; then
    _ai2fa_ok "TOTP is configured"
    echo "mode: $mode"
    echo "window: ${AI2FA_TOTP_WINDOW}"
    echo "secret: $(mask_secret "$secret")"
  else
    _ai2fa_info "TOTP is not configured"
    echo "mode: $mode"
  fi
}

subcmd="${1:-status}"
case "$subcmd" in
  setup|enable)
    shift
    cmd_setup "${1:-}"
    ;;
  verify)
    shift
    cmd_verify "${1:-}"
    ;;
  disable)
    cmd_disable
    ;;
  status)
    cmd_status
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    _ai2fa_err "Unknown totp command: $subcmd"
    usage
    exit 1
    ;;
esac
