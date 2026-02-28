# ai2fa Threat Model

## What ai2fa Is

A user-level identity verification layer for AI coding agents. It answers one question: **"Is the person at the keyboard the authorized user?"**

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Terminal    │     │  ai2fa       │     │  OOB Channel│
│  (untrusted │────▶│  (generates  │────▶│  (Telegram,  │
│   input)    │     │   OTP,       │     │   Slack...)  │
│             │     │   stores     │     │             │
│             │     │   keyed      │     │  → user's   │
│             │     │   digest)    │     │    device    │
│             │     │             │     │              │
└─────────────┘     └──────┬──────┘     └─────────────┘
                           │
                    HMAC comparison
                    (never stores code)
```

## Threat Matrix

### Threats Mitigated

| Threat | Scenario | How ai2fa helps |
|--------|----------|-----------------|
| **Unauthorized terminal use** | Someone sits at your unlocked machine | They can't provide the OTP from your phone |
| **Config theft** | Someone copies your `.claude/` directory | Challenge phrase is in Keychain/pass, not plaintext. Canary traps detect them. |
| **Social engineering** | Someone impersonates you to the AI agent | They can't intercept the OOB code |
| **Replay attacks** | Reuse a previously valid code | Codes expire (default 5 min), challenge state deleted after use |
| **Brute force** | Guess the code | Online guesses lock after configurable failed attempts (default 3) and challenge expires quickly |
| **Offline cracking of challenge file** | Read local challenge state and brute-force | Challenge state stores only HMAC output; secret HMAC key lives in secure storage |
| **Policy bypass via prompt injection** | Attacker tries to talk the model into ignoring FAILED state | Optional `fail_action: terminate_parent` enforces hard-stop at process level |
| **Credential exposure** | AI agent accidentally prints secrets | OTP never appears in terminal output — only "SENT" |

### Threats NOT Mitigated

| Threat | Why |
|--------|-----|
| **Full machine compromise (root)** | If attacker has root, they can modify scripts, read Keychain, intercept everything. This is out of scope for any user-level tool. |
| **Compromised phone/device** | If attacker has your Telegram/Slack, they can read OTPs. Same limitation as all 2FA. |
| **Script tampering** | If attacker can modify `~/.ai2fa/` contents, they can bypass verification. Mitigate with filesystem permissions. |
| **AI model manipulation** | If the LLM itself is compromised or jailbroken, it could ignore verification instructions. ai2fa relies on the agent following its config. |
| **Side-channel attacks** | Timing attacks on hash comparison are theoretical but impractical at human-interaction speed. |

## Security Properties

### Code Never Exposed

The verification code is generated, immediately HMACed, and the original is sent via API call. At no point does the code appear in:
- Terminal stdout/stderr
- Log files
- Process listing (`ps`)
- Shell history
- Local challenge state (only keyed digest + timestamp + attempts are written)

### Challenge State Storage

The challenge file at `~/.ai2fa/challenge.state` contains:
1. HMAC-SHA256 digest of the code
2. Unix timestamp of generation
3. Attempt counter

File permissions: `chmod 600` (owner-only read/write).

### Credential Storage

Channel credentials (API tokens, webhook URLs) are stored in:
- **macOS:** Keychain (encrypted, requires user password/biometric to access)
- **Linux:** `pass` (GPG-encrypted)
- **Fallback:** `~/.ai2fa/secrets` with `chmod 600` (least secure)

The OTP HMAC key (`otp_hmac_key`) is stored in the same secure backend.

Never stored in config.yaml or any plaintext file.

## Canary Traps — Threat Detection

Canary projects are fake names stored in secure storage. They detect unauthorized users who:

1. Steal the agent's config file
2. See the "verify unfamiliar projects" instruction
3. Don't know which names are traps
4. Ask about a fake project, thinking it's real

When triggered:
- Silent alert to the real user via OOB channel
- Agent returns `CANARY` and plays along (honeypot behavior)
- Attacker has no indication they've been detected

## Recommendations

1. **Use Keychain or pass** — avoid the env/file backend for production use
2. **Keep your phone secure** — ai2fa is only as strong as your device security
3. **Lock your screen** — ai2fa protects against "walk-up" attacks, but prevention is better
4. **Don't share your OOB channel** — the Telegram chat, Slack DM, etc. should be private to you
5. **Review your agent's config regularly** — ensure the verification instructions haven't been tampered with
6. **Pick a security level that matches your tolerance** — `balanced` for daily use, `strict/paranoid` for higher-risk contexts
7. **Choose a failure policy intentionally** — `none` for soft-fail, `terminate_parent` for hard-fail enforcement
