# ai2fa + Any AI Agent

**ai2fa** works with any AI coding agent that can run shell commands. The pattern is the same everywhere.

## Requirements

- Agent can execute shell commands
- Agent reads a configuration/rules file at session start
- `ai2fa` is in the system PATH

## The Pattern

Add these instructions to your agent's config file (whatever it reads on startup):

```
On every new session, before doing any work:

1. Run: ai2fa send
   This sends a verification code to the user's device.

2. Ask the user: "What's the verification code?"

3. Run: ai2fa verify <CODE>
   Replace <CODE> with what the user provided.

4. If the output is "VERIFIED" — proceed with normal work.
   If the output starts with "FAILED" — refuse all work.
   Do not proceed until verification succeeds.
```

## Shell Command Reference

```bash
# Send a code → prints "SENT" on success
ai2fa send

# Verify a code → prints "VERIFIED" or "FAILED:*"
ai2fa verify A1B2C3D4E5F6

# Verify challenge phrase → prints "VERIFIED" or "FAILED:*"
ai2fa phrase "secret words"

# Check project name → prints "CLEAN" or "CANARY"
ai2fa check "ProjectName"
```

## Exit Codes

| Command | Success | Failure |
|---------|---------|---------|
| `ai2fa send` | 0 (prints SENT) | 1 |
| `ai2fa verify` | 0 (prints VERIFIED) | 1 (prints FAILED:*) |
| `ai2fa phrase` | 0 (prints VERIFIED) | 1 (prints FAILED:*) |
| `ai2fa check` | 0 (prints CLEAN or CANARY) | 1 |

## Optional Hard-Fail Mode

Set `fail_action: terminate_parent` in `~/.ai2fa/config.yaml` if you want
verification failure to signal and terminate the parent process instead of
only returning `FAILED:*`.

## Tested With

- Claude Code (Anthropic)
- Cursor
- Aider
- Custom agents via Claude Agent SDK, OpenAI Agents SDK

If you've tested with another agent, open a PR to add it here.
