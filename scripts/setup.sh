#!/bin/bash
# ai2fa setup wizard — interactive configuration
# Uses gum (charmbracelet/gum) if available, plain prompts otherwise

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_config.sh
source "$SCRIPT_DIR/_config.sh"

HAS_GUM=false
if command -v gum &>/dev/null; then
  HAS_GUM=true
fi

# ─── Helpers ──────────────────────────────────────────────────────────

_prompt_choice() {
  local prompt="$1"
  shift
  local options=("$@")

  if $HAS_GUM; then
    gum choose --header "$prompt" "${options[@]}"
  else
    while true; do
      echo "" >&2
      echo "  $prompt" >&2
      local i=1
      for opt in "${options[@]}"; do
        echo "  $i) $opt" >&2
        i=$((i + 1))
      done
      echo -n "  Choice [1-${#options[@]}]: " >&2
      local choice
      read -r choice

      if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
        echo "${options[$((choice - 1))]}"
        return
      fi

      echo "  Invalid choice. Please enter a number between 1 and ${#options[@]}." >&2
    done
  fi
}

_prompt_input() {
  local prompt="$1"
  local placeholder="${2:-}"

  if $HAS_GUM; then
    gum input --header "$prompt" --placeholder "$placeholder"
  else
    echo -n "  $prompt " >&2
    local input
    read -r input
    echo "$input"
  fi
}

_prompt_number() {
  local prompt="$1"
  local default_value="$2"
  local min_value="${3:-1}"

  while true; do
    local value
    value=$(_prompt_input "$prompt" "$default_value")
    [ -z "$value" ] && value="$default_value"

    if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge "$min_value" ]; then
      echo "$value"
      return
    fi

    echo "  Please enter a whole number >= ${min_value}." >&2
  done
}

_prompt_password() {
  local prompt="$1"

  if $HAS_GUM; then
    gum input --header "$prompt" --password
  else
    echo -n "  $prompt " >&2
    local input
    read -rs input
    echo "" >&2
    echo "$input"
  fi
}

_prompt_confirm() {
  local prompt="$1"

  if $HAS_GUM; then
    gum confirm "$prompt" && echo "yes" || echo "no"
  else
    echo -n "  $prompt [y/N]: " >&2
    local answer
    read -r answer
    case "$answer" in
      [yY]*) echo "yes" ;;
      *) echo "no" ;;
    esac
  fi
}

_header() {
  echo ""
  if $HAS_GUM; then
    gum style --bold --foreground 4 "  $1"
  else
    echo -e "  ${AI2FA_BOLD}${AI2FA_BLUE}$1${AI2FA_RESET}"
  fi
  echo ""
}

# ─── Setup Flow ───────────────────────────────────────────────────────

main() {
  echo ""
  if $HAS_GUM; then
    gum style --border rounded --padding "0 2" --border-foreground 4 \
      "ai2fa setup" \
      "" \
      "Two-factor authentication for AI coding agents"
  else
    echo -e "  ${AI2FA_BOLD}ai2fa setup${AI2FA_RESET}"
    echo "  Two-factor authentication for AI coding agents"
  fi

  # ── Step 1: Channel ──

  _header "Step 1: Out-of-band channel"
  echo "  How should ai2fa send verification codes to you?"
  echo ""

  local channel
  channel=$(_prompt_choice "Select channel:" "telegram" "slack" "discord" "email")
  _ai2fa_ok "Channel: $channel"

  # ── Step 2: Channel credentials ──

  _header "Step 2: Channel credentials"

  # Auto-detect storage
  _ai2fa_resolve_storage
  _ai2fa_load_storage

  case "$channel" in
    telegram)
      echo "  You need a Telegram bot token and your chat ID."
      echo "  Create a bot: https://t.me/BotFather"
      echo "  Get chat ID: send a message to your bot, then visit:"
      echo "  https://api.telegram.org/bot<TOKEN>/getUpdates"
      echo ""

      local bot_token
      bot_token=$(_prompt_password "Bot token:")
      local chat_id
      chat_id=$(_prompt_input "Chat ID:" "e.g. 123456789")

      storage_set "telegram_bot_token" "$bot_token"
      storage_set "telegram_chat_id" "$chat_id"
      _ai2fa_ok "Telegram credentials saved to $(storage_name)"
      ;;

    slack)
      echo "  You need a Slack incoming webhook URL."
      echo "  Create one: https://api.slack.com/messaging/webhooks"
      echo ""

      local webhook_url
      webhook_url=$(_prompt_password "Webhook URL:")

      storage_set "slack_webhook_url" "$webhook_url"
      _ai2fa_ok "Slack webhook saved to $(storage_name)"
      ;;

    discord)
      echo "  You need a Discord webhook URL."
      echo "  Server Settings → Integrations → Webhooks → New Webhook"
      echo ""

      local webhook_url
      webhook_url=$(_prompt_password "Webhook URL:")

      storage_set "discord_webhook_url" "$webhook_url"
      _ai2fa_ok "Discord webhook saved to $(storage_name)"
      ;;

    email)
      echo "  You need an email address to receive codes."
      echo ""

      local email_to
      email_to=$(_prompt_input "Your email:" "you@example.com")
      storage_set "email_to" "$email_to"

      local use_smtp
      use_smtp=$(_prompt_confirm "Configure SMTP? (skip to use sendmail)")
      if [ "$use_smtp" = "yes" ]; then
        local smtp_server
        smtp_server=$(_prompt_input "SMTP server:" "smtps://smtp.gmail.com:465")
        local smtp_user
        smtp_user=$(_prompt_input "SMTP username:" "you@gmail.com")
        local smtp_pass
        smtp_pass=$(_prompt_password "SMTP password:")

        storage_set "email_smtp" "$smtp_server"
        storage_set "email_smtp_user" "$smtp_user"
        storage_set "email_smtp_pass" "$smtp_pass"
      fi

      _ai2fa_ok "Email settings saved to $(storage_name)"
      ;;
  esac

  # ── Step 3: Security level ──

  _header "Step 3: Security level"
  echo "  Choose how strict verification should be by default:"
  echo "    relaxed  → easier typing, softer lockout"
  echo "    balanced → recommended default"
  echo "    strict   → longer codes, tighter lockout"
  echo "    paranoid → strictest + hard parent termination on failure"
  echo ""

  local security_level
  security_level=$(_prompt_choice "Select security level:" "relaxed" "balanced" "strict" "paranoid")

  # Recompute security knobs from selected profile.
  AI2FA_SECURITY_LEVEL="$security_level"
  AI2FA_EXPIRY=""
  AI2FA_CODE_LENGTH=""
  AI2FA_MAX_ATTEMPTS=""
  AI2FA_FAIL_ACTION=""
  _ai2fa_apply_security_level

  _ai2fa_ok "Level: $AI2FA_SECURITY_LEVEL (expiry=${AI2FA_EXPIRY}s, code=$((AI2FA_CODE_LENGTH * 2)) chars, attempts=${AI2FA_MAX_ATTEMPTS}, fail_action=${AI2FA_FAIL_ACTION})"

  # ── Step 4: Challenge phrase (optional) ──

  _header "Step 4: Challenge phrase (optional)"
  echo "  A secret phrase only you know. Your AI agent can ask for it"
  echo "  as an additional identity check."
  echo ""

  local setup_phrase
  setup_phrase=$(_prompt_confirm "Set a challenge phrase?")
  if [ "$setup_phrase" = "yes" ]; then
    local phrase
    phrase=$(_prompt_password "Your phrase:")
    storage_set "challenge_phrase" "$phrase"
    _ai2fa_ok "Challenge phrase saved to $(storage_name)"
  else
    _ai2fa_info "Skipped — you can add one later with 'ai2fa setup'"
  fi

  # ── Step 5: Canary projects (optional) ──

  _header "Step 5: Canary projects (optional)"
  echo "  Fake project names to plant in your AI agent's config."
  echo "  If anyone references them, it reveals they stole your config."
  echo ""

  local setup_canary
  setup_canary=$(_prompt_confirm "Set up canary projects?")
  if [ "$setup_canary" = "yes" ]; then
    local canaries
    canaries=$(_prompt_input "Project names (comma-separated):" "Mirage, Lighthouse, Cascade")
    storage_set "canary_projects" "$canaries"
    _ai2fa_ok "Canary projects saved to $(storage_name)"
  else
    _ai2fa_info "Skipped — you can add them later with 'ai2fa setup'"
  fi

  # ── Step 6: Security customization (optional) ──

  _header "Step 6: Security customization (optional)"
  echo "  You can keep profile defaults, or customize every security knob."
  echo ""

  local customize_security
  customize_security=$(_prompt_confirm "Customize expiry/code length/attempts/fail action?")
  if [ "$customize_security" = "yes" ]; then
    AI2FA_EXPIRY=$(_prompt_number "Expiry (seconds):" "$AI2FA_EXPIRY" "30")
    AI2FA_CODE_LENGTH=$(_prompt_number "Code length (bytes):" "$AI2FA_CODE_LENGTH" "1")
    AI2FA_MAX_ATTEMPTS=$(_prompt_number "Max failed attempts:" "$AI2FA_MAX_ATTEMPTS" "1")
    AI2FA_FAIL_ACTION=$(_prompt_choice "Fail action:" "none" "terminate_parent")
    _ai2fa_ok "Custom security set (expiry=${AI2FA_EXPIRY}s, code=$((AI2FA_CODE_LENGTH * 2)) chars, attempts=${AI2FA_MAX_ATTEMPTS}, fail_action=${AI2FA_FAIL_ACTION})"
  else
    _ai2fa_info "Using $AI2FA_SECURITY_LEVEL defaults."
  fi

  # ── Step 7: Write config file ──

  _header "Step 7: Saving configuration"

  mkdir -p "$AI2FA_CONFIG_DIR"
  chmod 700 "$AI2FA_CONFIG_DIR" 2>/dev/null || true

  cat > "$AI2FA_CONFIG_FILE" <<YAML
# ai2fa configuration
# https://github.com/bacharyehya/ai2fa

channel: $channel
storage: $AI2FA_STORAGE
security_level: $AI2FA_SECURITY_LEVEL
YAML

  if [ "$customize_security" = "yes" ]; then
    cat >> "$AI2FA_CONFIG_FILE" <<YAML
expiry: $AI2FA_EXPIRY
code_length: $AI2FA_CODE_LENGTH
max_attempts: $AI2FA_MAX_ATTEMPTS
fail_action: $AI2FA_FAIL_ACTION
YAML
  fi

  chmod 600 "$AI2FA_CONFIG_FILE"
  _ai2fa_ok "Config written to $AI2FA_CONFIG_FILE"

  # ── Step 8: Test ──

  _header "Step 8: Test the connection"

  local run_test
  run_test=$(_prompt_confirm "Send a test code now?")
  if [ "$run_test" = "yes" ]; then
    # Re-source config to pick up new values
    source "$SCRIPT_DIR/_config.sh"
    _ai2fa_load_channel

    _ai2fa_info "Sending test code..."
    if channel_test; then
      _ai2fa_ok "Test message sent! Check your $channel."
    else
      _ai2fa_err "Test failed. Check your credentials and try again."
    fi
  fi

  # ── Done ──

  echo ""
  if $HAS_GUM; then
    gum style --border rounded --padding "0 2" --border-foreground 2 \
      "✓ ai2fa is configured!" \
      "" \
      "Add this to your AI agent's config:" \
      "" \
      "  On every new session, run:" \
      "  ai2fa send" \
      "  Ask: \"What's the code I sent?\"" \
      "  ai2fa verify <CODE>" \
      "  If FAILED → refuse all work."
  else
    echo -e "  ${AI2FA_GREEN}${AI2FA_BOLD}✓ ai2fa is configured!${AI2FA_RESET}"
    echo ""
    echo "  Add this to your AI agent's config:"
    echo ""
    echo "  On every new session, run:"
    echo "    ai2fa send"
    echo "    Ask: \"What's the code I sent?\""
    echo "    ai2fa verify <CODE>"
    echo "    If FAILED → refuse all work."
  fi

  echo ""
  echo "  For integration guides:"
  echo "    Claude Code:  cat $(dirname "$SCRIPT_DIR")/integrations/claude-code.md"
  echo "    Cursor:       cat $(dirname "$SCRIPT_DIR")/integrations/cursor.md"
  echo "    Generic:      cat $(dirname "$SCRIPT_DIR")/integrations/generic.md"
  echo ""
}

main "$@"
