#!/bin/bash
# ai2fa self-test suite
# Runs regression checks without external test frameworks.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AI2FA_BIN="$ROOT/bin/ai2fa"

TESTS_RUN=0
TESTS_PASSED=0

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local context="$3"
  if [ "$expected" != "$actual" ]; then
    die "$context (expected='$expected' actual='$actual')"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    die "$context (missing '$needle' in '$haystack')"
  fi
}

assert_file_exists() {
  local path="$1"
  local context="$2"
  [ -f "$path" ] || die "$context (missing file: $path)"
}

assert_file_missing() {
  local path="$1"
  local context="$2"
  [ ! -f "$path" ] || die "$context (unexpected file: $path)"
}

mkd() {
  mktemp -d "${TMPDIR:-/tmp}/ai2fa-selftest.XXXXXX"
}

get_effective_settings() {
  local config_dir="$1"
  AI2FA_CONFIG_DIR="$config_dir" ROOT="$ROOT" bash -lc '
    source "$ROOT/scripts/_config.sh"
    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" \
      "$AI2FA_SECURITY_LEVEL" \
      "$AI2FA_EXPIRY" \
      "$AI2FA_CODE_LENGTH" \
      "$AI2FA_MAX_ATTEMPTS" \
      "$AI2FA_FAIL_ACTION" \
      "$AI2FA_TOTP_MODE" \
      "$AI2FA_TOTP_WINDOW" \
      "$AI2FA_HTTP_CONNECT_TIMEOUT" \
      "$AI2FA_HTTP_MAX_TIME" \
      "$AI2FA_HTTP_RETRIES"
  '
}

run_test() {
  local name="$1"
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  "$@"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  log "PASS: $name"
}

test_syntax() {
  local f
  for f in "$ROOT"/bin/ai2fa "$ROOT"/scripts/*.sh "$ROOT"/channels/*.sh "$ROOT"/storage/*.sh; do
    bash -n "$f"
  done
}

test_profile_matrix() {
  local dir out

  # Default -> low profile
  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "low,300,6,3,none,off,1,5,15,2" "$out" "default profile"

  # New level names
  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: minimal
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "minimal,600,4,5,none,off,1,5,15,2" "$out" "minimal profile"

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: medium
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "medium,180,8,2,none,off,1,5,15,2" "$out" "medium profile"

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: high
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "high,120,8,1,none,off,1,5,15,2" "$out" "high profile"

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: extra_high
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "extra_high,60,8,1,terminate_parent,off,1,5,15,2" "$out" "extra_high profile"

  # Legacy names remain compatible
  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: relaxed
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "minimal,600,4,5,none,off,1,5,15,2" "$out" "legacy relaxed profile"

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: balanced
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "low,300,6,3,none,off,1,5,15,2" "$out" "legacy balanced profile"

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: strict
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "medium,180,8,2,none,off,1,5,15,2" "$out" "legacy strict profile"

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: paranoid
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "extra_high,60,8,1,terminate_parent,off,1,5,15,2" "$out" "legacy paranoid profile"

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: medium
expiry: 999
code_length: 10
max_attempts: 9
fail_action: none
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "medium,999,10,9,none,off,1,5,15,2" "$out" "profile overrides"
}

test_profile_sanitize_and_fallback() {
  local dir out

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: ultra
expiry: abc
code_length: 0
max_attempts: nope
fail_action: explode
totp_mode: maybe
totp_window: nope
http_connect_timeout: nope
http_max_time: -1
http_retries: nope
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "low,300,6,3,none,off,1,5,15,2" "$out" "invalid profile/settings sanitize"

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: extra_high
fail_action: terminate-prent
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "extra_high,60,8,1,none,off,1,5,15,2" "$out" "invalid fail_action safe fallback"
}

test_inline_comment_parsing() {
  local dir out

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: telegram
storage: env
security_level: medium # production profile
expiry: 999 # temporary
code_length: 10 # custom
max_attempts: 4 # custom
fail_action: none # safe
YAML
  out="$(get_effective_settings "$dir")"
  assert_eq "medium,999,10,4,none,off,1,5,15,2" "$out" "inline comments"
}

phrase_hash() {
  local salt="$1"
  local phrase="$2"
  printf '%s:%s' "$salt" "$phrase" | openssl dgst -sha256 | awk '{print $NF}'
}

make_hmac_challenge() {
  local dir="$1"
  local code="$2"
  local key mac

  key="$(openssl rand -hex 32)"
  printf 'otp_hmac_key=%s\n' "$key" > "$dir/secrets"
  chmod 600 "$dir/secrets"

  mac="$(printf '%s' "$code" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$key" | awk '{print $NF}')"
  cat > "$dir/challenge.state" <<EOF
MAC=$mac
TIMESTAMP=$(date +%s)
ATTEMPTS=0
EOF
  chmod 600 "$dir/challenge.state"
}

test_verify_lockout_and_success() {
  local dir out rc

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: balanced
max_attempts: 2
fail_action: none
YAML
  make_hmac_challenge "$dir" "ABCDEF123456"

  set +e
  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-otp.sh" BADBAD 2>&1)"
  rc=$?
  set -e
  assert_eq "1" "$rc" "wrong code should fail"
  assert_eq "FAILED:WRONG_CODE" "$out" "wrong code output"

  set +e
  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-otp.sh" BADBAD 2>&1)"
  rc=$?
  set -e
  assert_eq "1" "$rc" "lockout should fail"
  assert_eq "FAILED:LOCKED" "$out" "lockout output"
  assert_file_missing "$dir/challenge.state" "challenge should be removed after lock"

  make_hmac_challenge "$dir" "ABCDEF123456"
  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-otp.sh" "ABCDEF123456" 2>&1)"
  assert_eq "VERIFIED" "$out" "valid code should verify"
  assert_file_missing "$dir/challenge.state" "challenge should be removed after success"
}

test_corrupt_challenge_output() {
  local dir out rc

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: balanced
fail_action: none
YAML
  printf 'otp_hmac_key=%s\n' "$(openssl rand -hex 32)" > "$dir/secrets"
  cat > "$dir/challenge.state" <<'EOF'
TIMESTAMP=123
ATTEMPTS=0
EOF

  set +e
  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-otp.sh" ABC 2>&1)"
  rc=$?
  set -e
  assert_eq "1" "$rc" "corrupt challenge should fail"
  assert_eq "FAILED:CORRUPT_CHALLENGE" "$out" "corrupt challenge output"
}

test_code_normalization() {
  local dir out rc

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: balanced
fail_action: none
YAML
  make_hmac_challenge "$dir" "ABCDEF123456"

  set +e
  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-otp.sh" "ab-cd ef12 3456" 2>&1)"
  rc=$?
  set -e
  assert_eq "0" "$rc" "normalized input should verify"
  assert_eq "VERIFIED" "$out" "normalized output"
}

test_send_failure_cleanup() {
  local dir out rc

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: balanced
fail_action: none
YAML

  set +e
  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/send-otp.sh" 2>&1)"
  rc=$?
  set -e
  assert_eq "1" "$rc" "send without webhook should fail"
  assert_contains "$out" "Slack webhook URL not configured" "send failure error"
  assert_file_missing "$dir/challenge.state" "send failure should clean challenge state"
  assert_file_exists "$dir/secrets" "send failure should still create secrets file for key"
  assert_contains "$(cat "$dir/secrets")" "otp_hmac_key=" "HMAC key persisted"
}

test_terminate_parent_semantics() {
  local dir parent_script out_file rc out

  dir="$(mkd)"
  out_file="$dir/verify.out"
  parent_script="$dir/parent.sh"

  cat > "$parent_script" <<EOF
#!/bin/bash
set -euo pipefail
ROOT="$ROOT"
dir="$dir"
cat > "\$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: relaxed
fail_action: terminate_parent
YAML
key=\$(openssl rand -hex 32)
printf 'otp_hmac_key=%s\n' "\$key" > "\$dir/secrets"
mac=\$(printf '%s' "ABCDEF123456" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:\$key" | awk '{print \$NF}')
cat > "\$dir/challenge.state" <<STATE
MAC=\$mac
TIMESTAMP=\$(date +%s)
ATTEMPTS=0
STATE
AI2FA_CONFIG_DIR="\$dir" "\$ROOT/scripts/verify-otp.sh" WRONG > "\$dir/verify.out" 2>&1
EOF
  chmod +x "$parent_script"

  set +e
  bash "$parent_script" >/dev/null 2>&1
  rc=$?
  set -e

  [ "$rc" -ge 128 ] || die "terminate_parent should signal-kill bash parent (rc=$rc)"
  assert_file_exists "$out_file" "terminate_parent should emit FAILED output before signal"
  out="$(cat "$out_file")"
  assert_contains "$out" "FAILED:WRONG_CODE" "terminate_parent FAILED output (bash)"

  if command -v zsh >/dev/null 2>&1; then
    set +e
    zsh "$parent_script" >/dev/null 2>&1
    rc=$?
    set -e
    [ "$rc" -ge 128 ] || die "terminate_parent should signal-kill zsh parent (rc=$rc)"
    assert_file_exists "$out_file" "terminate_parent should emit FAILED output before signal (zsh)"
    out="$(cat "$out_file")"
    assert_contains "$out" "FAILED:WRONG_CODE" "terminate_parent FAILED output (zsh)"
  fi
}

test_fail_action_override_behavior() {
  local dir out rc parent_script out_file

  # Case 1: paranoid profile + fail_action none should not terminate parent.
  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: paranoid
fail_action: none
YAML
  make_hmac_challenge "$dir" "ABCDEF123456"
  set +e
  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-otp.sh" WRONG 2>&1)"
  rc=$?
  set -e
  assert_eq "1" "$rc" "paranoid override none rc"
  assert_eq "FAILED:LOCKED" "$out" "paranoid override none output"

  # Case 2: relaxed profile + terminate_parent should kill parent shell.
  dir="$(mkd)"
  out_file="$dir/verify.out"
  parent_script="$dir/parent.sh"
  cat > "$parent_script" <<EOF
#!/bin/bash
set -euo pipefail
ROOT="$ROOT"
dir="$dir"
cat > "\$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: relaxed
fail_action: terminate_parent
YAML
key=\$(openssl rand -hex 32)
printf 'otp_hmac_key=%s\n' "\$key" > "\$dir/secrets"
mac=\$(printf '%s' "ABCDEF123456" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:\$key" | awk '{print \$NF}')
cat > "\$dir/challenge.state" <<STATE
MAC=\$mac
TIMESTAMP=\$(date +%s)
ATTEMPTS=0
STATE
AI2FA_CONFIG_DIR="\$dir" "\$ROOT/scripts/verify-otp.sh" WRONG > "\$dir/verify.out" 2>&1
EOF
  chmod +x "$parent_script"

  set +e
  bash "$parent_script" >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" -ge 128 ] || die "relaxed override terminate_parent should signal-kill parent (rc=$rc)"
  assert_file_exists "$out_file" "override terminate_parent output file"
  assert_contains "$(cat "$out_file")" "FAILED:WRONG_CODE" "override terminate_parent output"
}

test_mocked_e2e_balanced() {
  local dir fakebin payload out_send code out_verify

  dir="$(mkd)"
  fakebin="$dir/fakebin"
  mkdir -p "$fakebin"

  cat > "$fakebin/curl" <<'CURL'
#!/bin/bash
set -euo pipefail
if [ ! -t 0 ]; then
  cat > "${AI2FA_TEST_PAYLOAD_FILE:-/tmp/ai2fa-payload}"
fi
printf "200"
CURL
  chmod +x "$fakebin/curl"

  cat > "$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: balanced
fail_action: none
YAML
  cat > "$dir/secrets" <<'SEC'
slack_webhook_url=https://example.test/hook
SEC
  chmod 600 "$dir/secrets"

  payload="$dir/payload.json"
  out_send="$(AI2FA_TEST_PAYLOAD_FILE="$payload" AI2FA_CONFIG_DIR="$dir" PATH="$fakebin:/usr/bin:/bin" "$ROOT/scripts/send-otp.sh")"
  assert_eq "SENT" "$out_send" "mocked send output"

  code="$(grep -oE '[0-9A-F]{8,32}' "$payload" | head -1)"
  assert_eq "12" "${#code}" "balanced code length"

  out_verify="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-otp.sh" "$code")"
  assert_eq "VERIFIED" "$out_verify" "mocked e2e verify"
}

test_mocked_e2e_strict_code_length() {
  local dir fakebin payload code

  dir="$(mkd)"
  fakebin="$dir/fakebin"
  mkdir -p "$fakebin"

  cat > "$fakebin/curl" <<'CURL'
#!/bin/bash
set -euo pipefail
if [ ! -t 0 ]; then
  cat > "${AI2FA_TEST_PAYLOAD_FILE:-/tmp/ai2fa-payload}"
fi
printf "200"
CURL
  chmod +x "$fakebin/curl"

  cat > "$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: medium
fail_action: none
YAML
  cat > "$dir/secrets" <<'SEC'
slack_webhook_url=https://example.test/hook
SEC
  chmod 600 "$dir/secrets"

  payload="$dir/payload.json"
  AI2FA_TEST_PAYLOAD_FILE="$payload" AI2FA_CONFIG_DIR="$dir" PATH="$fakebin:/usr/bin:/bin" "$ROOT/scripts/send-otp.sh" >/dev/null
  code="$(grep -oE '[0-9A-F]{8,32}' "$payload" | head -1)"
  assert_eq "16" "${#code}" "medium code length"
}

test_phrase_hash_and_legacy_plaintext() {
  local dir out rc salt hash

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: low
YAML

  salt="$(openssl rand -hex 16)"
  hash="$(phrase_hash "$salt" "horse battery staple")"
  cat > "$dir/secrets" <<SEC
challenge_phrase_salt=$salt
challenge_phrase_hash=$hash
SEC
  chmod 600 "$dir/secrets"

  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-phrase.sh" "horse battery staple" 2>&1)"
  assert_eq "VERIFIED" "$out" "hashed phrase should verify"

  set +e
  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-phrase.sh" "wrong phrase" 2>&1)"
  rc=$?
  set -e
  assert_eq "1" "$rc" "wrong hashed phrase should fail"
  assert_eq "FAILED:WRONG_PHRASE" "$out" "wrong hashed phrase output"

  # Legacy plaintext phrase remains backward compatible and is migrated to hash.
  cat > "$dir/secrets" <<'SEC'
challenge_phrase=legacy phrase
SEC
  chmod 600 "$dir/secrets"

  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-phrase.sh" "legacy phrase" 2>&1)"
  assert_eq "VERIFIED" "$out" "legacy plaintext phrase should verify"
  assert_contains "$(cat "$dir/secrets")" "challenge_phrase_hash=" "legacy phrase migrated to hash"
}

gen_totp() {
  local secret="$1"
  python3 - "$secret" <<'PY'
import base64
import hashlib
import hmac
import struct
import time
import sys

secret = sys.argv[1].strip().replace(" ", "").upper()
pad = "=" * ((8 - len(secret) % 8) % 8)
key = base64.b32decode(secret + pad, casefold=True)
counter = int(time.time()) // 30
msg = struct.pack(">Q", counter)
h = hmac.new(key, msg, hashlib.sha1).digest()
offset = h[-1] & 0x0F
dbc = ((h[offset] & 0x7F) << 24) | (h[offset + 1] << 16) | (h[offset + 2] << 8) | h[offset + 3]
print(f"{dbc % 1000000:06d}")
PY
}

test_totp_verify_and_replay_protection() {
  local dir secret code out rc

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: low
totp_mode: required
YAML

  secret="JBSWY3DPEHPK3PXP"
  cat > "$dir/secrets" <<SEC
totp_secret=$secret
totp_last_counter=-1
SEC
  chmod 600 "$dir/secrets"

  code="$(gen_totp "$secret")"
  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-totp.sh" "$code" 2>&1)"
  assert_eq "VERIFIED" "$out" "totp should verify once"

  set +e
  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-totp.sh" "$code" 2>&1)"
  rc=$?
  set -e
  assert_eq "1" "$rc" "totp replay should fail"
  assert_eq "FAILED:REPLAY" "$out" "totp replay output"
}

test_verify_fallback_to_totp() {
  local dir secret code out

  dir="$(mkd)"
  cat > "$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: low
totp_mode: fallback
YAML

  secret="JBSWY3DPEHPK3PXP"
  cat > "$dir/secrets" <<SEC
totp_secret=$secret
totp_last_counter=-1
SEC
  chmod 600 "$dir/secrets"

  code="$(gen_totp "$secret")"
  out="$(AI2FA_CONFIG_DIR="$dir" "$ROOT/scripts/verify-otp.sh" "$code" 2>&1)"
  assert_eq "VERIFIED" "$out" "verify should fallback to totp when no challenge exists"
}

test_canary_matching_and_payload_escape() {
  local dir fakebin payload out

  dir="$(mkd)"
  fakebin="$dir/fakebin"
  mkdir -p "$fakebin"

  cat > "$fakebin/curl" <<'CURL'
#!/bin/bash
set -euo pipefail
if [ ! -t 0 ]; then
  cat > "${AI2FA_TEST_PAYLOAD_FILE:-/tmp/ai2fa-payload}"
fi
printf "200"
CURL
  chmod +x "$fakebin/curl"

  cat > "$dir/config.yaml" <<'YAML'
channel: slack
storage: env
security_level: low
YAML
  cat > "$dir/secrets" <<'SEC'
slack_webhook_url=https://example.test/hook
canary_projects=Mirage,  Project "Alpha"  ,Shadow
SEC
  chmod 600 "$dir/secrets"

  payload="$dir/payload.json"
  out="$(AI2FA_TEST_PAYLOAD_FILE="$payload" AI2FA_CONFIG_DIR="$dir" PATH="$fakebin:/usr/bin:/bin" "$ROOT/scripts/canary-check.sh" 'Project "Alpha"' 2>&1)"
  assert_eq "CANARY" "$out" "quoted canary should match"
  assert_contains "$(cat "$payload")" 'Project \"Alpha\"' "payload should JSON-escape quoted project name"

  out="$(AI2FA_TEST_PAYLOAD_FILE="$payload" AI2FA_CONFIG_DIR="$dir" PATH="$fakebin:/usr/bin:/bin" "$ROOT/scripts/canary-check.sh" "shadow" 2>&1)"
  assert_eq "CANARY" "$out" "case-insensitive canary should match"

  out="$(AI2FA_TEST_PAYLOAD_FILE="$payload" AI2FA_CONFIG_DIR="$dir" PATH="$fakebin:/usr/bin:/bin" "$ROOT/scripts/canary-check.sh" "not-a-canary" 2>&1)"
  assert_eq "CLEAN" "$out" "non-canary should remain clean"
}

test_setup_non_gum_default_flow() {
  local dir

  dir="$(mkd)"
  printf '2\nhttps://example.test/webhook\n2\nn\nn\n1\nn\nn\n' | \
    AI2FA_STORAGE=env AI2FA_CONFIG_DIR="$dir" PATH="/usr/bin:/bin" bash "$ROOT/scripts/setup.sh" >/dev/null 2>&1

  assert_file_exists "$dir/config.yaml" "setup default config written"
  assert_contains "$(cat "$dir/config.yaml")" "security_level: low" "setup default profile"
}

test_setup_non_gum_custom_flow() {
  local dir

  dir="$(mkd)"
  printf '2\nhttps://example.test/webhook\n5\nn\nn\n2\ny\n240\n7\n4\n1\nn\n' | \
    AI2FA_STORAGE=env AI2FA_CONFIG_DIR="$dir" PATH="/usr/bin:/bin" bash "$ROOT/scripts/setup.sh" >/dev/null 2>&1

  assert_contains "$(cat "$dir/config.yaml")" "security_level: extra_high" "setup custom profile"
  assert_contains "$(cat "$dir/config.yaml")" "totp_mode: fallback" "setup totp mode"
  assert_contains "$(cat "$dir/config.yaml")" "expiry: 240" "setup custom expiry"
  assert_contains "$(cat "$dir/config.yaml")" "code_length: 7" "setup custom code length"
  assert_contains "$(cat "$dir/config.yaml")" "max_attempts: 4" "setup custom attempts"
  assert_contains "$(cat "$dir/config.yaml")" "fail_action: none" "setup custom fail_action"
}

test_setup_invalid_numeric_retry() {
  local dir err_file

  dir="$(mkd)"
  err_file="$dir/setup.err"

  printf '2\nhttps://example.test/webhook\n2\nn\nn\n1\ny\nabc\n240\n0\n6\n-1\n3\n1\nn\n' | \
    AI2FA_STORAGE=env AI2FA_CONFIG_DIR="$dir" PATH="/usr/bin:/bin" bash "$ROOT/scripts/setup.sh" >/dev/null 2>"$err_file"

  assert_contains "$(cat "$dir/config.yaml")" "expiry: 240" "setup retry expiry"
  assert_contains "$(cat "$dir/config.yaml")" "code_length: 6" "setup retry code length"
  assert_contains "$(cat "$dir/config.yaml")" "max_attempts: 3" "setup retry attempts"
  assert_contains "$(cat "$dir/config.yaml")" "fail_action: none" "setup retry fail action"

  local count
  count="$(grep -c "Please enter a whole number" "$err_file")"
  assert_eq "3" "$count" "invalid numeric prompt count"
}

main() {
  run_test "shell syntax" test_syntax
  run_test "profile matrix" test_profile_matrix
  run_test "profile sanitize/fallback" test_profile_sanitize_and_fallback
  run_test "inline comment parsing" test_inline_comment_parsing
  run_test "verify lockout + success cleanup" test_verify_lockout_and_success
  run_test "corrupt challenge output" test_corrupt_challenge_output
  run_test "verify code normalization" test_code_normalization
  run_test "send failure cleanup" test_send_failure_cleanup
  run_test "parent termination semantics" test_terminate_parent_semantics
  run_test "fail action override behavior" test_fail_action_override_behavior
  run_test "mocked e2e balanced" test_mocked_e2e_balanced
  run_test "mocked e2e medium code length" test_mocked_e2e_strict_code_length
  run_test "phrase hash + legacy migration" test_phrase_hash_and_legacy_plaintext
  run_test "totp verify + replay" test_totp_verify_and_replay_protection
  run_test "verify fallback to totp" test_verify_fallback_to_totp
  run_test "canary matching + payload escaping" test_canary_matching_and_payload_escape
  run_test "setup non-gum default flow" test_setup_non_gum_default_flow
  run_test "setup non-gum custom flow" test_setup_non_gum_custom_flow
  run_test "setup non-gum numeric retry flow" test_setup_invalid_numeric_retry

  log "PASS: all tests (${TESTS_PASSED}/${TESTS_RUN})"
}

main "$@"
