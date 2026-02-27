#!/bin/bash
# ai2fa config system — sourced by every script
# Loads ~/.ai2fa/config.yaml (simple key: value, no YAML library needed)

AI2FA_VERSION="0.1.0"
AI2FA_CONFIG_DIR="${AI2FA_CONFIG_DIR:-$HOME/.ai2fa}"
AI2FA_CONFIG_FILE="$AI2FA_CONFIG_DIR/config.yaml"

# Defaults
AI2FA_CHANNEL="${AI2FA_CHANNEL:-}"
AI2FA_STORAGE="${AI2FA_STORAGE:-}"
AI2FA_EXPIRY="${AI2FA_EXPIRY:-300}"
AI2FA_CODE_LENGTH="${AI2FA_CODE_LENGTH:-3}"

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
      # Strip quotes if present
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"

      case "$key" in
        channel)       AI2FA_CHANNEL="$value" ;;
        storage)       AI2FA_STORAGE="$value" ;;
        expiry)        AI2FA_EXPIRY="$value" ;;
        code_length)   AI2FA_CODE_LENGTH="$value" ;;
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

# Resolve storage backend
_ai2fa_resolve_storage() {
  if [ -z "$AI2FA_STORAGE" ]; then
    AI2FA_STORAGE="$(_ai2fa_detect_os)"
  fi
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
_ai2fa_resolve_storage
