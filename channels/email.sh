#!/bin/bash
# ai2fa channel adapter — email via curl SMTP or sendmail

channel_send() {
  local message="$1"

  local email_to="${AI2FA_EMAIL_TO:-}"
  local email_from="${AI2FA_EMAIL_FROM:-}"
  local email_smtp="${AI2FA_EMAIL_SMTP:-}"

  if [ -z "$email_to" ]; then
    email_to=$(storage_get "email_to")
  fi
  if [ -z "$email_from" ]; then
    email_from=$(storage_get "email_from")
  fi
  if [ -z "$email_smtp" ]; then
    email_smtp=$(storage_get "email_smtp")
  fi

  if [ -z "$email_to" ]; then
    echo "ERROR: Email recipient not configured" >&2
    echo "Run 'ai2fa setup' to configure, or set email_to" >&2
    return 1
  fi

  # Try sendmail first, then curl SMTP
  if command -v sendmail &>/dev/null && [ -z "$email_smtp" ]; then
    echo -e "Subject: ai2fa verification\nFrom: ${email_from:-ai2fa@localhost}\nTo: $email_to\n\n$message" | sendmail "$email_to"
  elif [ -n "$email_smtp" ]; then
    local smtp_user
    local smtp_pass
    local body_file
    local args
    local rc
    smtp_user=$(storage_get "email_smtp_user")
    smtp_pass=$(storage_get "email_smtp_pass")
    body_file="$(mktemp "${TMPDIR:-/tmp}/ai2fa-email.XXXXXX")"
    chmod 600 "$body_file"
    printf "Subject: ai2fa verification\nFrom: %s\nTo: %s\n\n%s\n" "${email_from:-ai2fa@localhost}" "$email_to" "$message" > "$body_file"

    args=(
      --url "$email_smtp"
      --mail-from "${email_from:-ai2fa@localhost}"
      --mail-rcpt "$email_to"
      -T "$body_file"
    )
    if [ -n "$smtp_user" ]; then
      args+=(--user "$smtp_user:$smtp_pass")
    fi
    rc=0
    _ai2fa_curl "${args[@]}" || rc=$?
    rm -f "$body_file"
    [ "$rc" -eq 0 ] || return "$rc"
  else
    echo "ERROR: No sendmail found and no SMTP server configured" >&2
    return 1
  fi
}

channel_name() {
  echo "Email"
}

channel_test() {
  channel_send "ai2fa test — if you see this, your email channel is working."
}
