# Contributing to ai2fa

## Adding a Channel

Channels live in `channels/`. Each channel is a single bash script that exports three functions:

```bash
# channels/signal.sh

channel_send() {
  local message="$1"
  # Send the message via your channel
  # Return 0 on success, 1 on failure
}

channel_name() {
  echo "Signal"
}

channel_test() {
  channel_send "🔐 ai2fa test — if you see this, your Signal channel is working."
}
```

### Channel Contract

- `channel_send <message>` — Send a message. Return 0 on success.
- `channel_name` — Return human-readable name.
- `channel_test` — Send a test message.

### Credential Access

Use `storage_get` / `storage_set` for credentials (storage adapter is loaded before the channel):

```bash
local token=$(storage_get "signal_token")
```

Or read from config variables (set in `_config.sh`):

```bash
local token="${AI2FA_SIGNAL_TOKEN:-}"
if [ -z "$token" ]; then
  token=$(storage_get "signal_token")
fi
```

After creating the channel file, add its config keys to `scripts/_config.sh` in the config parser.

## Adding a Storage Backend

Storage backends live in `storage/`. Each exports five functions:

```bash
# storage/vault.sh

storage_get() {
  local key="$1"
  # Return the value, or empty string if not found
}

storage_set() {
  local key="$1"
  local value="$2"
  # Store the key-value pair
}

storage_delete() {
  local key="$1"
  # Remove the key
}

storage_exists() {
  local key="$1"
  # Return 0 if exists, 1 if not
}

storage_name() {
  echo "HashiCorp Vault"
}
```

### Storage Contract

- Keys are simple strings like `telegram_bot_token`, `challenge_phrase`
- Values are strings (no binary)
- `storage_get` returns empty string if key doesn't exist
- `storage_exists` returns exit code 0/1

## Code Style

- Pure bash, no external dependencies beyond `bash`, `curl`, `openssl`
- `set -euo pipefail` in all scripts
- Use `_ai2fa_` prefix for internal functions
- Respect `NO_COLOR` env var
- Test on both macOS and Linux if possible

## Testing

```bash
# Full regression suite (same checks as CI)
bash scripts/selftest.sh

# Manual channel flow
ai2fa test

# Runtime health
ai2fa status
```

## Submitting

1. Fork the repo
2. Create a branch: `git checkout -b add-signal-channel`
3. Add your channel/storage/feature
4. Test it
5. Open a PR with a clear description
