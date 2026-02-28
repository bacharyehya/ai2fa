#!/bin/bash
# ai2fa channel adapter — Discord webhook

channel_send() {
  local message="$1"

  local webhook_url="${AI2FA_DISCORD_WEBHOOK_URL:-}"
  if [ -z "$webhook_url" ]; then
    webhook_url=$(storage_get "discord_webhook_url")
  fi

  if [ -z "$webhook_url" ]; then
    echo "ERROR: Discord webhook URL not configured" >&2
    echo "Run 'ai2fa setup' to configure, or set discord_webhook_url" >&2
    return 1
  fi

  local response
  local payload
  payload=$(printf '{"content":"%s"}' "$(_ai2fa_json_escape "$message")")

  response=$(printf '%s' "$payload" | curl -s -o /dev/null -w "%{http_code}" -X POST \
    "$webhook_url" \
    -H "Content-Type: application/json" \
    --data-binary @-)

  if [ "$response" = "200" ] || [ "$response" = "204" ]; then
    return 0
  else
    echo "ERROR: Discord send failed (HTTP $response)" >&2
    return 1
  fi
}

channel_name() {
  echo "Discord"
}

channel_test() {
  channel_send "🔐 ai2fa test — if you see this, your Discord channel is working."
}
