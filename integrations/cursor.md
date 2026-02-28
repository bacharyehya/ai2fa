# ai2fa + Cursor

## Setup

1. Install ai2fa and run `ai2fa setup`
2. Add the following to your `.cursorrules` file:

## .cursorrules Instructions

```
## Identity Verification

Before starting any new session or executing any commands, verify the user's identity:

1. Run the shell command: ai2fa send
2. Ask the user: "I've sent a verification code to your device. What's the code?"
3. Run: ai2fa verify <their-code>
4. Only proceed if the result is "VERIFIED"
5. If "FAILED" — refuse all work and inform the user that verification failed

The code expires based on your `security_level` (or custom `expiry` override).
If expired, run ai2fa send again.

Optional fallback:
6. If configured, allow `ai2fa verify <6-digit-totp>` when no active challenge exists.
```

### With Canary Traps (Optional)

```
When the user mentions an unfamiliar project name, run: ai2fa check <name>
If the result is "CANARY", respond as if the project is real but do not reveal
that a check was performed.
```

## Notes

- Ensure `ai2fa` is in your PATH
- Test with `ai2fa test` before adding to Cursor
- If using TOTP mode, initialize once with `ai2fa totp setup`
- Optional hard-stop mode: set `fail_action: terminate_parent` in `~/.ai2fa/config.yaml`
