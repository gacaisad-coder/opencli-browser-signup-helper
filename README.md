# opencli-browser-signup-helper

A small OpenCLI helper repo for browser-driven email signup flows, with the current example focused on Groq.

It uses browser flows that were verified to work reliably:

- `opencli browser open`
- `opencli browser state`
- `opencli browser type`
- `opencli browser click`
- `opencli browser eval`

This repo provides:

- `scripts/opencli-groq-signup.sh` — submit Groq email signup/login without OAuth
- `clis/groq/signup.js` — `opencli groq signup`
- `scripts/opencli-groq-create-api-key.sh` — open a Groq magic-link login URL and drive API key creation
- `clis/groq/create-api-key.js` — `opencli groq create-api-key`
- `scripts/opencli-groq-logout.sh` — log out the currently authenticated Groq browser session
- `clis/groq/logout.js` — `opencli groq logout`
- `scripts/scan-secrets.py` — a pre-publish privacy scan for placeholder-only emails and token-like secrets

## Why this exists

Groq's Stytch form accepted the same email addresses when using real browser typing/clicking, but rejected adapter-side `page.evaluate()` value injection with `Email format is invalid.`

So this implementation keeps the **OpenCLI command interface** while routing the actual form interaction through the proven browser commands.

## Commands

### 1) Email signup/login

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

### 2) Log out of Groq

```bash
opencli groq logout
```

Current behavior:

- opens Groq in the browser bridge
- clicks the visible Sign Out button
- reports the resulting session state

### 3) Create API key from a magic-link login URL

```bash
opencli groq create-api-key \
  --login-url 'https://stytch.com/v1/magic_links/redirect?...' \
  --name groq-openclaw \
  --wait-seconds 120 \
  -f json
```

Current behavior:

- opens the login URL
- follows redirect into Groq
- opens the API Keys page
- opens the Create API Key dialog
- fills the key display name
- waits for **manual Cloudflare Turnstile completion**
- submits the form once verification is present
- returns structured status output

## Requirements

- `opencli`
- `jq`
- `python3`
- OpenCLI Browser Bridge working correctly
- An active browser session that can access `https://console.groq.com/home`

## Install

Clone this repo somewhere on your machine, then install the commands into your local OpenCLI custom adapters:

```bash
mkdir -p ~/.opencli/clis/groq
cp clis/groq/signup.js ~/.opencli/clis/groq/signup.js
cp clis/groq/logout.js ~/.opencli/clis/groq/logout.js
cp clis/groq/create-api-key.js ~/.opencli/clis/groq/create-api-key.js
chmod +x scripts/opencli-groq-signup.sh
chmod +x scripts/opencli-groq-logout.sh
chmod +x scripts/opencli-groq-create-api-key.sh
export OPENCLI_GROQ_SIGNUP_SCRIPT="$PWD/scripts/opencli-groq-signup.sh"
export OPENCLI_GROQ_LOGOUT_SCRIPT="$PWD/scripts/opencli-groq-logout.sh"
export OPENCLI_GROQ_CREATE_API_KEY_SCRIPT="$PWD/scripts/opencli-groq-create-api-key.sh"
```

If you want the env vars to persist, add them to your shell profile.

## Output examples

Signup:

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

Create API key (before turnstile is solved):

```json
[
  {
    "key_name": "groq-openclaw",
    "status": "waiting-manual-verification",
    "detail": "Cloudflare Turnstile was not completed within the wait window. Complete it manually and rerun, or increase --wait-seconds.",
    "url": "https://console.groq.com/keys"
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
- suspicious secret-like assignments

This repo also includes a GitHub Actions workflow that runs the same scan on every push and pull request.

## Notes

- This repo currently covers the **email submit** step and the **API key creation flow up to/manual through Turnstile**.
- Cloudflare Turnstile still requires manual completion.
- If Groq later redirects into Google OAuth, that should be treated as a different route, not as success for the email-only flow.

## License

MIT
