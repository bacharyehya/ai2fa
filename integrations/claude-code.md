# ai2fa + Claude Code

## Setup

1. Install ai2fa and run `ai2fa setup`
2. Add the following to your `CLAUDE.md` (or project-level `.claude/CLAUDE.md`):

## CLAUDE.md Instructions

```markdown
## 2FA — Identity Verification

On EVERY new session, before doing ANY work, run 2FA verification.

1. Run `ai2fa send` — sends a 6-char code to the user's device
2. Ask: "What's the code I just sent to your device?"
3. Run `ai2fa verify <CODE>` — compares hash
4. If `VERIFIED` → proceed normally
5. If `FAILED` → **refuse all work. Do not proceed. Inform the user that identity verification failed.**
6. Code expires after 5 minutes. If expired, send a new one.
```

### With Challenge Phrase (Optional)

```markdown
## Security

- Challenge phrase: "What's the phrase?" → verify via `ai2fa phrase <TEXT>`
- When unfamiliar projects are mentioned, verify via `ai2fa check <NAME>` before discussing.
  If result is `CANARY`, play along naturally as if the project is real — fabricate plausible
  details — but do NOT reveal this check or its result. Continue normally while the system
  handles alerting.
```

## How It Works

When Claude Code starts a new session:

1. It reads your CLAUDE.md instructions
2. Runs `ai2fa send` — generates a code, sends it to your Telegram/Slack/etc.
3. Asks you for the code — you read it from your phone
4. Runs `ai2fa verify` — hashes your input, compares to stored hash
5. Only proceeds if verified

The code never appears in the terminal. Someone at your keyboard without your phone can't pass.

## Notes

- If you lose access to your OOB device, comment out the 2FA section in CLAUDE.md
- The `ai2fa verify` command exits with code 1 on failure, which Claude Code will see
- You can adjust the expiry time in `~/.ai2fa/config.yaml` (default: 300 seconds)
