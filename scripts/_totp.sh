#!/bin/bash
# ai2fa TOTP helpers

_ai2fa_totp_require_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    _ai2fa_err "python3 is required for TOTP support"
    return 1
  fi
  return 0
}

_ai2fa_totp_generate_secret() {
  _ai2fa_totp_require_python || return 1
  python3 - <<'PY'
import base64
import secrets

raw = secrets.token_bytes(20)
secret = base64.b32encode(raw).decode("ascii").rstrip("=")
print(secret)
PY
}

_ai2fa_totp_otpauth_uri() {
  local secret="$1"
  local account="$2"
  local issuer="${3:-ai2fa}"
  local account_enc
  local issuer_enc

  _ai2fa_totp_require_python || return 1
  account_enc="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$account")"
  issuer_enc="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$issuer")"
  printf 'otpauth://totp/%s:%s?secret=%s&issuer=%s&algorithm=SHA1&digits=6&period=30\n' "$issuer_enc" "$account_enc" "$secret" "$issuer_enc"
}

# Prints the matched counter on success; returns non-zero otherwise.
_ai2fa_totp_match_counter() {
  local secret="$1"
  local code="$2"
  local window="${3:-1}"
  local now="${4:-}"

  _ai2fa_totp_require_python || return 1
  python3 - "$secret" "$code" "$window" "$now" <<'PY'
import base64
import binascii
import hashlib
import hmac
import re
import struct
import sys
import time

secret = sys.argv[1].strip().replace(" ", "").upper()
code = sys.argv[2].strip()
window = int(sys.argv[3])
now_arg = sys.argv[4].strip()
now = int(now_arg) if now_arg else int(time.time())

if not re.fullmatch(r"\d{6}", code):
    raise SystemExit(2)

pad = "=" * ((8 - len(secret) % 8) % 8)
try:
    key = base64.b32decode(secret + pad, casefold=True)
except (binascii.Error, ValueError):
    raise SystemExit(3)

counter = now // 30
for current in range(counter - window, counter + window + 1):
    if current < 0:
        continue
    msg = struct.pack(">Q", current)
    digest = hmac.new(key, msg, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    dbc = (
        ((digest[offset] & 0x7F) << 24)
        | (digest[offset + 1] << 16)
        | (digest[offset + 2] << 8)
        | digest[offset + 3]
    )
    expected = f"{dbc % 1_000_000:06d}"
    if hmac.compare_digest(expected, code):
        print(current)
        raise SystemExit(0)

raise SystemExit(1)
PY
}
