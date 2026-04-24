# opencli-browser-signup-helper

A small OpenCLI helper repo for browser-driven email signup flows, with the current example focused on Groq.

It uses the browser flow that was verified to work reliably:

- `opencli browser open`
- `opencli browser state`
- `opencli browser type`
- `opencli browser click`

This repo provides:

- `scripts/opencli-groq-signup.sh` — the proven signup helper
- `clis/groq/signup.js` — an `opencli groq signup` command that shells out to the helper script
- `scripts/scan-secrets.py` — a pre-publish privacy scan for placeholder-only emails and token-like secrets

## Why this exists

Groq's Stytch form accepted the same email addresses when using real browser typing/clicking, but rejected adapter-side `page.evaluate()` value injection with `Email format is invalid.`

So this implementation keeps the **OpenCLI command interface** while routing the actual form interaction through the proven browser commands.

## Command shape

```bash
opencli groq signup \
  --email-domain example.com \
  --name-mode random \
  --prefix groq
```

Rules:

- `--name-mode` defaults to `random`
- if `--email` is provided, it overrides and ignores `--email-domain`, `--name-mode`, and `--prefix`

Explicit email example:

```bash
opencli groq signup --email demo@example.com -f json
```

## Requirements

- `opencli`
- `jq`
- `python3`
- OpenCLI Browser Bridge working correctly
- An active browser session that can access `https://console.groq.com/home`

## Install

Clone this repo somewhere on your machine, then install the command into your local OpenCLI custom adapters:

```bash
mkdir -p ~/.opencli/clis/groq
cp clis/groq/signup.js ~/.opencli/clis/groq/signup.js
chmod +x scripts/opencli-groq-signup.sh
export OPENCLI_GROQ_SIGNUP_SCRIPT="$PWD/scripts/opencli-groq-signup.sh"
```

If you want the env var to persist, add it to your shell profile.

## Usage

Generated email:

```bash
opencli groq signup --email-domain example.com --prefix groq -f json
```

Explicit email:

```bash
opencli groq signup --email demo@example.com -f json
```

## Output example

```json
[
  {
    "email": "groq-cz0729j3@example.com",
    "source": "generated",
    "status": "check-your-email",
    "detail": "Groq accepted the email and asked to check inbox.",
    "url": "https://console.groq.com/home"
  }
]
```

## Privacy and safety

Before publishing changes, run:

```bash
python3 scripts/scan-secrets.py
```

The scanner is intentionally conservative. It checks for:

- non-placeholder email addresses
- token-like strings such as GitHub tokens or `sk-...`
- suspicious secret-related keywords in code or docs

This repo also includes a GitHub Actions workflow that runs the same scan on every push and pull request.

## Notes

- This repo only covers the **email submit** step.
- If Groq later redirects into Google OAuth, that should be treated as a different route, not as success for the email-only flow.
- If you want to continue the full flow, the next step is reading the magic-link email and opening it.

## License

MIT
