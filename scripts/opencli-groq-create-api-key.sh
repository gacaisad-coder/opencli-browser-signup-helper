#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/opencli-groq-create-api-key.sh --login-url <url> [--name groq-openclaw]

What it does:
- opens the Groq magic-link login URL
- waits for redirect into Groq
- opens API Keys
- opens the Create API Key dialog
- fills the display name
- waits for manual Cloudflare Turnstile completion
- submits the form after verification is present
- reports the observed result state

Notes:
- Cloudflare Turnstile must currently be completed manually in the browser.
- This helper does not print existing secrets or environment values.
EOF
}

need_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required binary: $1" >&2
    exit 1
  }
}

LOGIN_URL=""
KEY_NAME="groq-openclaw"
WAIT_SECONDS=120
POLL_INTERVAL=2
FORMAT="table"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --login-url)
      LOGIN_URL="${2:-}"
      shift 2
      ;;
    --name)
      KEY_NAME="${2:-}"
      shift 2
      ;;
    --wait-seconds)
      WAIT_SECONDS="${2:-}"
      shift 2
      ;;
    --poll-interval)
      POLL_INTERVAL="${2:-}"
      shift 2
      ;;
    -f|--format)
      FORMAT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

need_bin opencli
need_bin python3

if [[ -z "$LOGIN_URL" ]]; then
  echo "--login-url is required" >&2
  exit 1
fi

opencli browser open "$LOGIN_URL" >/dev/null
opencli browser wait time 5 >/dev/null
STATE_OUTPUT="$(opencli browser state)"

if ! printf '%s' "$STATE_OUTPUT" | grep -q 'API Keys\|Dashboard\|GroqCloud'; then
  echo "Login redirect did not appear to land in Groq." >&2
  echo "$STATE_OUTPUT" >&2
  exit 1
fi

API_KEYS_INDEX="$(printf '%s\n' "$STATE_OUTPUT" | sed -n 's/.*\[\([0-9]\+\)\]<a href=\/keys.*/\1/p' | head -n1)"
if [[ -n "$API_KEYS_INDEX" ]]; then
  opencli browser click "$API_KEYS_INDEX" >/dev/null
else
  opencli browser open 'https://console.groq.com/keys' >/dev/null
fi
opencli browser wait time 3 >/dev/null
STATE_OUTPUT="$(opencli browser state)"

CREATE_INDEX="$(printf '%s\n' "$STATE_OUTPUT" | sed -n 's/.*\[\([0-9]\+\)\]<button .*data-testid=keys-page-create-button.*/\1/p' | head -n1)"
if [[ -z "$CREATE_INDEX" ]]; then
  CREATE_INDEX="$(printf '%s\n' "$STATE_OUTPUT" | sed -n '/Create API Key/ { s/.*\[\([0-9]\+\)\]<button.*/\1/p; }' | head -n1)"
fi
if [[ -z "$CREATE_INDEX" ]]; then
  echo "Failed to locate Create API Key button." >&2
  echo "$STATE_OUTPUT" >&2
  exit 1
fi
opencli browser click "$CREATE_INDEX" >/dev/null
opencli browser wait time 2 >/dev/null
STATE_OUTPUT="$(opencli browser state)"

INPUT_INDEX="$(printf '%s\n' "$STATE_OUTPUT" | sed -n 's/.*\[\([0-9]\+\)\]<input .*name=keyName.*/\1/p' | head -n1)"
if [[ -z "$INPUT_INDEX" ]]; then
  echo "Failed to locate key name input." >&2
  echo "$STATE_OUTPUT" >&2
  exit 1
fi
opencli browser type "$INPUT_INDEX" "$KEY_NAME" >/dev/null
opencli browser wait time 1 >/dev/null

START_TS="$(date +%s)"
VERIFIED="false"
while true; do
  NOW_TS="$(date +%s)"
  ELAPSED=$((NOW_TS - START_TS))
  if (( ELAPSED >= WAIT_SECONDS )); then
    break
  fi

  CHECK_OUTPUT="$(opencli browser eval "(() => { const input = document.querySelector('input[name=\"cf-turnstile-response\"]'); return JSON.stringify({present: !!input, value: input?.value || ''}); })()")"
  if printf '%s' "$CHECK_OUTPUT" | grep -q '"present":true'; then
    TOKEN_VALUE="$(printf '%s\n' "$CHECK_OUTPUT" | sed -n 's/.*"value":"\([^"]*\)".*/\1/p' | head -n1)"
    if [[ -n "$TOKEN_VALUE" ]]; then
      VERIFIED="true"
      break
    fi
  fi
  opencli browser wait time "$POLL_INTERVAL" >/dev/null
done

STATUS=""
DETAIL=""
CURRENT_URL='https://console.groq.com/keys'

if [[ "$VERIFIED" != "true" ]]; then
  STATUS="waiting-manual-verification"
  DETAIL="Cloudflare Turnstile was not completed within the wait window. Complete it manually and rerun, or increase --wait-seconds."
else
  opencli browser eval "(() => { const form = document.querySelector('div[role=dialog] form'); if (!form) return JSON.stringify({submitted:false, reason:'no-form'}); if (typeof form.requestSubmit === 'function') { form.requestSubmit(); return JSON.stringify({submitted:true, method:'requestSubmit'}); } form.dispatchEvent(new Event('submit', {bubbles:true, cancelable:true})); return JSON.stringify({submitted:true, method:'dispatchEvent'}); })()" >/dev/null
  opencli browser wait time 5 >/dev/null
  POST_STATE="$(opencli browser state)"
  URL_OUTPUT="$(opencli browser get url)"
  CURRENT_URL="$(printf '%s\n' "$URL_OUTPUT" | sed -n 's/.*"url": "\(.*\)".*/\1/p' | head -n1)"
  if [[ -z "$CURRENT_URL" ]]; then
    CURRENT_URL="$(printf '%s\n' "$URL_OUTPUT" | sed -n 's/^URL: //p' | head -n1)"
  fi
  if [[ -z "$CURRENT_URL" ]]; then
    CURRENT_URL='https://console.groq.com/keys'
  fi

  if printf '%s' "$POST_STATE" | grep -q '(No keys)'; then
    STATUS="submitted-no-visible-key-yet"
    DETAIL="Submitted after verification, but the page still shows no keys. Recheck the browser dialog/state."
  elif printf '%s' "$POST_STATE" | grep -q 'Secret Key\|API Keys'; then
    STATUS="submitted"
    DETAIL="Submitted after manual verification. Inspect the browser for the newly created key or confirmation dialog."
  else
    STATUS="submitted-unknown-state"
    DETAIL="Submitted after manual verification, but the resulting UI state was not recognized."
  fi
fi

python3 - <<PY
import csv, json, sys
row = {
  'key_name': ${KEY_NAME@Q},
  'status': ${STATUS@Q},
  'detail': ${DETAIL@Q},
  'url': ${CURRENT_URL@Q},
}
fmt = ${FORMAT@Q}
if fmt == 'json':
    print(json.dumps([row], ensure_ascii=False, indent=2))
elif fmt == 'csv':
    writer = csv.DictWriter(sys.stdout, fieldnames=list(row.keys()))
    writer.writeheader()
    writer.writerow(row)
else:
    for k, v in row.items():
        print(f"{k}: {v}")
PY
