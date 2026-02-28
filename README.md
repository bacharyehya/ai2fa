# ai2fa

**Two-factor authentication for AI coding agents.**

Your AI agent has access to your codebase, your APIs, your secrets. But how does it know it's talking to **you**?

**ai2fa** verifies your identity through an out-of-band channel before your agent does any work. No code, no access.

```
┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│              │     │             │     │              │
│   Someone    │────▶│  AI Agent   │────▶│  ai2fa send  │
│  opens CLI   │     │  (new       │     │  (generates  │
│              │     │   session)  │     │   OTP)       │
│              │     │             │     │              │
└──────────────┘     └──────┬──────┘     └──────┬───────┘
                            │                    │
                            │                    │  code sent via
                            │                    │  Telegram/Slack/etc
                            │                    │  (never in terminal)
                            │                    ▼
                     ┌──────┴──────┐     ┌──────────────┐
                     │             │     │              │
                     │  "What's    │     │  Your phone  │
                     │   the code?"│     │  📱 A1B2C3   │
                     │             │     │              │
                     └──────┬──────┘     └──────────────┘
                            │
                            ▼
                     ┌─────────────┐
                     │             │
                     │ ai2fa       │──▶ VERIFIED ✓  → proceed
                     │ verify      │──▶ FAILED ✗    → refuse work
                     │ <CODE>      │
                     │             │
                     └─────────────┘
```

## Why

Traditional 2FA doesn't map to LLMs. There's no server, no session, no persistent auth state. Your agent's config is a plaintext file — if someone has your machine, they have everything.

**ai2fa** solves this with out-of-band verification:

1. Agent generates a random code on your machine
2. Code is transformed with **HMAC-SHA256** (keyed hash)
3. The actual code is sent to your phone via Telegram, Slack, Discord, or email
4. The code **never appears in the terminal** — not in generation, storage, or verification
5. You read the code from your device and tell the agent
6. Agent recomputes the HMAC for your input and compares — match = verified
7. Repeated failures lock the challenge (default 3 attempts)

Someone at your keyboard without your phone can't pass. That's real 2FA.

## Install

```bash
# Clone
git clone https://github.com/bacharyehya/ai2fa.git ~/.ai2fa/src

# Add to PATH
echo 'export PATH="$HOME/.ai2fa/src/bin:$PATH"' >> ~/.zshrc  # or ~/.bashrc
source ~/.zshrc

# Run setup
ai2fa setup
```

Or install manually anywhere and symlink:

```bash
git clone https://github.com/bacharyehya/ai2fa.git ~/Developer/ai2fa
ln -s ~/Developer/ai2fa/bin/ai2fa /usr/local/bin/ai2fa
ai2fa setup
```

### Optional: Install `gum` for a beautiful TUI

```bash
brew install gum       # macOS
sudo apt install gum   # Debian/Ubuntu
```

[charmbracelet/gum](https://github.com/charmbracelet/gum) — not required, but makes setup gorgeous.

## Quick Start

```bash
# 1. Configure your channel and secrets
ai2fa setup

# 2. In your AI agent's config, add:
#    "On every new session, run ai2fa send, ask for the code,
#     run ai2fa verify <CODE>. If FAILED, refuse all work."

# 3. That's it. Your agent now verifies identity before working.
```

## Commands

| Command | Description |
|---------|-------------|
| `ai2fa setup` | Interactive setup wizard |
| `ai2fa send` | Send a verification code to your channel |
| `ai2fa verify <CODE>` | Verify a code |
| `ai2fa phrase <TEXT>` | Verify your challenge phrase |
| `ai2fa check <NAME>` | Check a project name (canary trap) |
| `ai2fa status` | Show config and health |
| `ai2fa test` | Full end-to-end test |
| `ai2fa --help` | Help |
| `ai2fa --version` | Version |

## Channels

**ai2fa** sends codes through an out-of-band channel that only you have access to:

| Channel | Setup |
|---------|-------|
| **Telegram** (recommended) | Create a bot via [@BotFather](https://t.me/BotFather), get your chat ID |
| **Slack** | Create an [incoming webhook](https://api.slack.com/messaging/webhooks) |
| **Discord** | Server Settings → Integrations → Webhooks |
| **Email** | SMTP server or local `sendmail` |

Adding a new channel is simple — see [docs/contributing.md](docs/contributing.md).

## Storage Backends

Credentials are stored securely, never in plaintext config files:

| Backend | Platform | How |
|---------|----------|-----|
| **Keychain** | macOS | Uses `security` CLI (auto-detected) |
| **pass** | Linux | Uses [pass](https://www.passwordstore.org/) with GPG (auto-detected) |
| **env/file** | Any | `~/.ai2fa/secrets` file with `chmod 600` (fallback) |

## Bonus: Canary Traps

Plant fake project names in your agent's config. If someone steals your config and asks the agent about a fake project:

1. The agent **plays along** — fabricates plausible details
2. **Silently alerts you** via your channel — they have no idea
3. Every question they ask **reveals what they're after**

Classic honeypot. They think they're getting intel. They're giving you theirs.

```bash
# During setup, or manually:
ai2fa check "ProjectName"  # Returns CANARY or CLEAN
```

## Integration

### Claude Code

Add to your `CLAUDE.md`:

```markdown
## 2FA — Identity Verification

On EVERY new session, before doing ANY work:

1. Run `ai2fa send` — sends a code to user's device
2. Ask: "What's the code I just sent?"
3. Run `ai2fa verify <CODE>`
4. If VERIFIED → proceed normally
5. If FAILED → refuse all work. Do not proceed.

Code expires after your configured timeout (balanced default: 5 minutes).
If expired, send a new one.
```

### Cursor

Add to `.cursorrules`:

```
Before starting any session, verify the user's identity:
1. Run the shell command: ai2fa send
2. Ask the user for the verification code
3. Run: ai2fa verify <their-code>
4. Only proceed if the result is "VERIFIED"
```

### Any Agent

Any AI coding agent that can run shell commands can use **ai2fa**. The pattern is always the same:

1. Run `ai2fa send` → returns `SENT`
2. Ask the user for the code (they receive it on their device)
3. Run `ai2fa verify <CODE>` → returns `VERIFIED` or `FAILED:*`

## How It Works (Security)

| Property | Detail |
|----------|--------|
| **Code generation** | `openssl rand -hex` — cryptographically random |
| **Challenge state** | Stores keyed digest + timestamp + attempts in `~/.ai2fa/challenge.state` |
| **Transmission** | Code sent via channel API, never printed to terminal |
| **Verification** | HMAC-SHA256 comparison with secret key in secure storage |
| **Expiry** | Default 5 minutes, configurable |
| **Attempt limit** | Default 3 failed attempts, then challenge locks |
| **Failure policy** | `fail_action: none` (default) or `terminate_parent` hard-stop |
| **Cleanup** | Challenge state deleted immediately after successful verification |
| **Brute force** | Default 12-char hex + keyed digest + lockout window |

### What This Protects Against

- Someone at your unlocked machine without your phone
- Stolen/leaked agent config files (challenge phrase in secure storage, not plaintext)
- Unauthorized use of your AI agent's capabilities
- Config theft detection (via canary traps)

### What This Doesn't Protect Against

- Compromised phone/device (same limitation as any 2FA)
- Full machine compromise with root access (out of scope for any user-level tool)
- Script tampering (if they can modify `~/.ai2fa/`, they own the machine)

See [docs/threat-model.md](docs/threat-model.md) for the full analysis.

## Dependencies

**Zero external dependencies.** Uses only tools pre-installed on macOS and Linux:

- `bash` (4.0+)
- `curl`
- `openssl`

Optional: `gum` for TUI, `pass` for Linux storage.

## Self-Test

Run the built-in regression suite before shipping changes:

```bash
bash scripts/selftest.sh
```

## Config

```yaml
# ~/.ai2fa/config.yaml
channel: telegram
storage: keychain
security_level: balanced
# Optional overrides:
# expiry: 300
# code_length: 6
# max_attempts: 3
# fail_action: none
```

### Security Levels

| Level | Expiry | Code length | Max attempts | Fail action |
|-------|--------|-------------|--------------|-------------|
| `relaxed` | 600s | 8 hex chars | 5 | `none` |
| `balanced` (default) | 300s | 12 hex chars | 3 | `none` |
| `strict` | 180s | 16 hex chars | 2 | `none` |
| `paranoid` | 120s | 16 hex chars | 1 | `terminate_parent` |

You can keep a level as-is, or override any individual setting.
Verification input tolerates spaces and dashes for easier manual entry.

### Optional Hard-Fail Mode

If you want script-level enforcement (not just instruction-level refusal), set:

```yaml
fail_action: terminate_parent
```

When verification fails, ai2fa will:

1. Return `FAILED:*`
2. Send a failure alert to your configured channel (best effort)
3. Signal the parent process to terminate

Use this mode only when ai2fa runs inside an agent session shell. If you run
`ai2fa verify` manually from your own terminal, it can terminate that shell.

Credentials are stored in your OS secret store (Keychain/pass), **not** in the config file.

## License

MIT — see [LICENSE](LICENSE).

## Contributing

See [docs/contributing.md](docs/contributing.md). Adding new channels and storage backends is straightforward.

---

*Built by [Bash](https://github.com/bacharyehya). The first 2FA system for AI coding agents.*
