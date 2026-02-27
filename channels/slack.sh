#!/bin/bash
# ai2fa channel adapter — Slack incoming webhook

channel_send() {
  local message="$1"

  local webhook_url="${AI2FA_SLACK_WEBHOOK_URL:-}"
  if [ -z "$webhook_url" ]; then
    webhook_url=$(storage_get "slack_webhook_url")
  fi

  if [ -z "$webhook_url" ]; then
    echo "ERROR: Slack webhook URL not configured" >&2
    echo "Run 'ai2fa setup' to configure, or set slack_webhook_url" >&2
    return 1
  fi

  local response
  response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "$webhook_url" \
    -H "Content-Type: application/json" \
    -d "{\"text\": \"$message\"}")

  if [ "$response" = "200" ]; then
    return 0
  else
    echo "ERROR: Slack send failed (HTTP $response)" >&2
    return 1
  fi
}

channel_name() {
  echo "Slack"
}

channel_test() {
  channel_send "🔐 ai2fa test — if you see this, your Slack channel is working."
}
