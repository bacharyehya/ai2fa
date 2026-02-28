#!/bin/bash
# ai2fa config system — sourced by every script
# Loads ~/.ai2fa/config.yaml (simple key: value, no YAML library needed)

AI2FA_VERSION="0.2.0"
AI2FA_CONFIG_DIR="${AI2FA_CONFIG_DIR:-$HOME/.ai2fa}"
AI2FA_CONFIG_FILE="$AI2FA_CONFIG_DIR/config.yaml"

# Defaults
AI2FA_CHANNEL="${AI2FA_CHANNEL:-}"
AI2FA_STORAGE="${AI2FA_STORAGE:-}"
AI2FA_SECURITY_LEVEL="${AI2FA_SECURITY_LEVEL:-low}"
AI2FA_EXPIRY="${AI2FA_EXPIRY:-}"
AI2FA_CODE_LENGTH="${AI2FA_CODE_LENGTH:-}"
AI2FA_MAX_ATTEMPTS="${AI2FA_MAX_ATTEMPTS:-}"
AI2FA_FAIL_ACTION="${AI2FA_FAIL_ACTION:-}"
AI2FA_TOTP_MODE="${AI2FA_TOTP_MODE:-}"
AI2FA_TOTP_WINDOW="${AI2FA_TOTP_WINDOW:-}"
AI2FA_HTTP_CONNECT_TIMEOUT="${AI2FA_HTTP_CONNECT_TIMEOUT:-}"
AI2FA_HTTP_MAX_TIME="${AI2FA_HTTP_MAX_TIME:-}"
AI2FA_HTTP_RETRIES="${AI2FA_HTTP_RETRIES:-}"
AI2FA_CHALLENGE_FILE="$AI2FA_CONFIG_DIR/challenge.state"

# Auto-detect OS for storage backend
_ai2fa_detect_os() {
  case "$(uname -s)" in
    Darwin*) echo "keychain" ;;
    Linux*)
      if command -v pass &>/dev/null; then
        echo "pass"
      else
        echo "env"
      fi
      ;;
    *) echo "env" ;;
  esac
}

# Parse config.yaml (simple key: value, ignores comments and blank lines)
_ai2fa_load_config() {
  if [ ! -f "$AI2FA_CONFIG_FILE" ]; then
    return 0
  fi

  while IFS= read -r line; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue

    # Parse key: value
    if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"
      # Strip inline comments for unquoted values.
      if [[ ! "$value" =~ ^\".*\"$ ]] && [[ ! "$value" =~ ^\'.*\'$ ]]; then
        value="${value%%[[:space:]]#*}"
      fi
      # Strip quotes if present
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"

      case "$key" in
        channel)       AI2FA_CHANNEL="$value" ;;
        storage)       AI2FA_STORAGE="$value" ;;
        security_level) AI2FA_SECURITY_LEVEL="$value" ;;
        expiry)        AI2FA_EXPIRY="$value" ;;
        code_length)   AI2FA_CODE_LENGTH="$value" ;;
        max_attempts)  AI2FA_MAX_ATTEMPTS="$value" ;;
        fail_action)   AI2FA_FAIL_ACTION="$value" ;;
        totp_mode)     AI2FA_TOTP_MODE="$value" ;;
        totp_window)   AI2FA_TOTP_WINDOW="$value" ;;
        http_connect_timeout) AI2FA_HTTP_CONNECT_TIMEOUT="$value" ;;
        http_max_time) AI2FA_HTTP_MAX_TIME="$value" ;;
        http_retries)  AI2FA_HTTP_RETRIES="$value" ;;
        # Channel-specific
        telegram_bot_token)   AI2FA_TELEGRAM_BOT_TOKEN="$value" ;;
        telegram_chat_id)     AI2FA_TELEGRAM_CHAT_ID="$value" ;;
        slack_webhook_url)    AI2FA_SLACK_WEBHOOK_URL="$value" ;;
        discord_webhook_url)  AI2FA_DISCORD_WEBHOOK_URL="$value" ;;
        email_to)             AI2FA_EMAIL_TO="$value" ;;
        email_from)           AI2FA_EMAIL_FROM="$value" ;;
        email_smtp)           AI2FA_EMAIL_SMTP="$value" ;;
      esac
    fi
  done < "$AI2FA_CONFIG_FILE"
}

# Apply a user-friendly security profile unless explicitly overridden.
_ai2fa_apply_security_level() {
  local level
  level=$(printf '%s' "$AI2FA_SECURITY_LEVEL" | tr '[:upper:]' '[:lower:]')
  local default_expiry
  local default_code_length
  local default_max_attempts
  local default_fail_action

  # Backward-compatible mapping from legacy names.
  case "$level" in
    relaxed) level="minimal" ;;
    balanced) level="low" ;;
    strict) level="medium" ;;
    paranoid) level="extra_high" ;;
  esac

  case "$level" in
    minimal)
      default_expiry="600"
      default_code_length="4"
      default_max_attempts="5"
      default_fail_action="none"
      ;;
    medium)
      default_expiry="180"
      default_code_length="8"
      default_max_attempts="2"
      default_fail_action="none"
      ;;
    high)
      default_expiry="120"
      default_code_length="8"
      default_max_attempts="1"
      default_fail_action="none"
      ;;
    extra_high)
      default_expiry="60"
      default_code_length="8"
      default_max_attempts="1"
      default_fail_action="terminate_parent"
      ;;
    low|"")
      level="low"
      default_expiry="300"
      default_code_length="6"
      default_max_attempts="3"
      default_fail_action="none"
      ;;
    *)
      level="low"
      default_expiry="300"
      default_code_length="6"
      default_max_attempts="3"
      default_fail_action="none"
      ;;
  esac

  AI2FA_SECURITY_LEVEL="$level"
  [ -z "$AI2FA_EXPIRY" ] && AI2FA_EXPIRY="$default_expiry"
  [ -z "$AI2FA_CODE_LENGTH" ] && AI2FA_CODE_LENGTH="$default_code_length"
  [ -z "$AI2FA_MAX_ATTEMPTS" ] && AI2FA_MAX_ATTEMPTS="$default_max_attempts"
  [ -z "$AI2FA_FAIL_ACTION" ] && AI2FA_FAIL_ACTION="$default_fail_action"

  if ! [[ "$AI2FA_EXPIRY" =~ ^[0-9]+$ ]] || [ "$AI2FA_EXPIRY" -lt 1 ]; then
    AI2FA_EXPIRY="$default_expiry"
  fi
  if ! [[ "$AI2FA_CODE_LENGTH" =~ ^[0-9]+$ ]] || [ "$AI2FA_CODE_LENGTH" -lt 1 ]; then
    AI2FA_CODE_LENGTH="$default_code_length"
  fi
  if ! [[ "$AI2FA_MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$AI2FA_MAX_ATTEMPTS" -lt 1 ]; then
    AI2FA_MAX_ATTEMPTS="$default_max_attempts"
  fi
  case "$AI2FA_FAIL_ACTION" in
    none|terminate_parent) ;;
    *) AI2FA_FAIL_ACTION="none" ;;
  esac

  if [ -z "$AI2FA_TOTP_MODE" ]; then
    AI2FA_TOTP_MODE="off"
  fi
  AI2FA_TOTP_MODE="$(printf '%s' "$AI2FA_TOTP_MODE" | tr '[:upper:]' '[:lower:]')"
  case "$AI2FA_TOTP_MODE" in
    off|fallback|required) ;;
    *) AI2FA_TOTP_MODE="off" ;;
  esac

  if ! [[ "$AI2FA_TOTP_WINDOW" =~ ^[0-9]+$ ]]; then
    AI2FA_TOTP_WINDOW="1"
  fi
  if [ "$AI2FA_TOTP_WINDOW" -gt 3 ]; then
    AI2FA_TOTP_WINDOW="3"
  fi

  if ! [[ "$AI2FA_HTTP_CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] || [ "$AI2FA_HTTP_CONNECT_TIMEOUT" -lt 1 ]; then
    AI2FA_HTTP_CONNECT_TIMEOUT="5"
  fi
  if ! [[ "$AI2FA_HTTP_MAX_TIME" =~ ^[0-9]+$ ]] || [ "$AI2FA_HTTP_MAX_TIME" -lt 1 ]; then
    AI2FA_HTTP_MAX_TIME="15"
  fi
  if ! [[ "$AI2FA_HTTP_RETRIES" =~ ^[0-9]+$ ]]; then
    AI2FA_HTTP_RETRIES="2"
  fi

  return 0
}

# Resolve storage backend
_ai2fa_resolve_storage() {
  if [ -z "$AI2FA_STORAGE" ]; then
    AI2FA_STORAGE="$(_ai2fa_detect_os)"
  fi
  return 0
}

# Source the appropriate storage adapter
_ai2fa_load_storage() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"

  local adapter="$script_dir/storage/${AI2FA_STORAGE}.sh"
  if [ -f "$adapter" ]; then
    # shellcheck source=/dev/null
    source "$adapter"
  else
    echo "ERROR: Unknown storage backend '$AI2FA_STORAGE'" >&2
    echo "Available: keychain, pass, env" >&2
    exit 1
  fi
}

# Source the appropriate channel adapter
_ai2fa_load_channel() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"

  local adapter="$script_dir/channels/${AI2FA_CHANNEL}.sh"
  if [ -f "$adapter" ]; then
    # shellcheck source=/dev/null
    source "$adapter"
  else
    echo "ERROR: Unknown channel '$AI2FA_CHANNEL'" >&2
    echo "Available: telegram, slack, discord, email" >&2
    exit 1
  fi
}

# Ensure ai2fa runtime directory exists and is private to the user.
_ai2fa_ensure_config_dir() {
  mkdir -p "$AI2FA_CONFIG_DIR"
  chmod 700 "$AI2FA_CONFIG_DIR" 2>/dev/null || true
}

# Minimal JSON escaping for webhook payload strings.
_ai2fa_json_escape() {
  local raw="$1"
  raw="${raw//\\/\\\\}"
  raw="${raw//\"/\\\"}"
  raw="${raw//$'\n'/\\n}"
  raw="${raw//$'\r'/\\r}"
  raw="${raw//$'\t'/\\t}"
  printf '%s' "$raw"
}

_ai2fa_hash_phrase() {
  local salt="$1"
  local phrase="$2"
  printf '%s:%s' "$salt" "$phrase" | openssl dgst -sha256 | awk '{print $NF}'
}

# Constant-time-ish comparison for equal-length secrets.
# Bash cannot guarantee strict constant time, but this avoids early exit on mismatch.
_ai2fa_secure_compare() {
  local left="$1"
  local right="$2"
  local left_len="${#left}"
  local right_len="${#right}"
  local max_len="$left_len"
  local idx left_ord right_ord diff

  if [ "$right_len" -gt "$max_len" ]; then
    max_len="$right_len"
  fi

  diff=$((left_len ^ right_len))
  for ((idx = 0; idx < max_len; idx++)); do
    if [ "$idx" -lt "$left_len" ]; then
      printf -v left_ord '%d' "'${left:idx:1}"
    else
      left_ord=0
    fi
    if [ "$idx" -lt "$right_len" ]; then
      printf -v right_ord '%d' "'${right:idx:1}"
    else
      right_ord=0
    fi
    diff=$((diff | (left_ord ^ right_ord)))
  done

  [ "$diff" -eq 0 ]
}

_ai2fa_curl() {
  curl --silent --show-error \
    --connect-timeout "$AI2FA_HTTP_CONNECT_TIMEOUT" \
    --max-time "$AI2FA_HTTP_MAX_TIME" \
    --retry "$AI2FA_HTTP_RETRIES" \
    --retry-delay 1 \
    "$@"
}

# Colors (respect NO_COLOR)
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  AI2FA_RED='\033[0;31m'
  AI2FA_GREEN='\033[0;32m'
  AI2FA_YELLOW='\033[0;33m'
  AI2FA_BLUE='\033[0;34m'
  AI2FA_BOLD='\033[1m'
  AI2FA_DIM='\033[2m'
  AI2FA_RESET='\033[0m'
else
  AI2FA_RED=''
  AI2FA_GREEN=''
  AI2FA_YELLOW=''
  AI2FA_BLUE=''
  AI2FA_BOLD=''
  AI2FA_DIM=''
  AI2FA_RESET=''
fi

# Logging helpers
_ai2fa_ok()    { echo -e "${AI2FA_GREEN}✓${AI2FA_RESET} $*"; }
_ai2fa_err()   { echo -e "${AI2FA_RED}✗${AI2FA_RESET} $*" >&2; }
_ai2fa_warn()  { echo -e "${AI2FA_YELLOW}!${AI2FA_RESET} $*"; }
_ai2fa_info()  { echo -e "${AI2FA_BLUE}→${AI2FA_RESET} $*"; }

# Init: load config + resolve storage
_ai2fa_load_config
_ai2fa_apply_security_level
_ai2fa_resolve_storage
