#!/bin/bash
# ai2fa channel adapter — Telegram Bot API

channel_send() {
  local message="$1"

  # Try config vars first, then storage
  local bot_token="${AI2FA_TELEGRAM_BOT_TOKEN:-}"
  local chat_id="${AI2FA_TELEGRAM_CHAT_ID:-}"

  if [ -z "$bot_token" ]; then
    bot_token=$(storage_get "telegram_bot_token")
  fi
  if [ -z "$chat_id" ]; then
    chat_id=$(storage_get "telegram_chat_id")
  fi

  if [ -z "$bot_token" ] || [ -z "$chat_id" ]; then
    echo "ERROR: Telegram credentials not configured" >&2
    echo "Run 'ai2fa setup' to configure, or set telegram_bot_token and telegram_chat_id" >&2
    return 1
  fi

  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "https://api.telegram.org/bot${bot_token}/sendMessage" \
    -d chat_id="$chat_id" \
    -d text="$message" \
    -d parse_mode="HTML")

  if [ "$response" = "200" ]; then
    return 0
  else
    echo "ERROR: Telegram send failed (HTTP $response)" >&2
    return 1
  fi
}

channel_name() {
  echo "Telegram"
}

channel_test() {
  channel_send "🔐 ai2fa test — if you see this, your Telegram channel is working."
}
