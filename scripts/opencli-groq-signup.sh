#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/opencli-groq-signup.sh --email-domain example.com [--name-mode random] [--prefix groq]
  ./scripts/opencli-groq-signup.sh --email demo@example.com

Rules:
- --name-mode defaults to random
- If --email is provided, --email-domain/--name-mode/--prefix are ignored
- This script uses the proven opencli browser type/click flow for Groq email signup
EOF
}

need_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required binary: $1" >&2
    exit 1
  }
}

normalize_domain() {
  local raw="$1"
  raw="${raw#@}"
  printf '%s' "$raw"
}

random_suffix() {
  python3 - <<'PY'
import random, string
chars = string.ascii_lowercase + string.digits
print(''.join(random.choice(chars) for _ in range(8)))
PY
}

EMAIL=""
EMAIL_DOMAIN=""
NAME_MODE="random"
PREFIX="groq"
URL="https://console.groq.com/home"
WAIT_SECONDS=2
FORMAT="table"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email)
      EMAIL="${2:-}"
      shift 2
      ;;
    --email-domain)
      EMAIL_DOMAIN="${2:-}"
      shift 2
      ;;
    --name-mode)
      NAME_MODE="${2:-}"
      shift 2
      ;;
    --prefix)
      PREFIX="${2:-}"
      shift 2
      ;;
    --url)
      URL="${2:-}"
      shift 2
      ;;
    --wait-seconds)
      WAIT_SECONDS="${2:-}"
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
need_bin jq

if [[ -n "$EMAIL" ]]; then
  FINAL_EMAIL="$EMAIL"
  SOURCE="explicit"
else
  EMAIL_DOMAIN="$(normalize_domain "$EMAIL_DOMAIN")"
  if [[ -z "$EMAIL_DOMAIN" ]]; then
    echo "--email-domain is required when --email is not provided" >&2
    exit 1
  fi
  if [[ "$NAME_MODE" != "random" ]]; then
    echo "Unsupported --name-mode: $NAME_MODE (only random is supported)" >&2
    exit 1
  fi
  FINAL_EMAIL="${PREFIX}-$(random_suffix)@${EMAIL_DOMAIN}"
  SOURCE="generated"
fi

opencli browser open "$URL" >/dev/null
STATE_OUTPUT="$(opencli browser state)"

if printf '%s' "$STATE_OUTPUT" | grep -qi 'Check your email'; then
  TRY_AGAIN_INDEX="$(printf '%s\n' "$STATE_OUTPUT" | sed -n 's/.*\[\([0-9]\+\)\]<button>Try again<.*/\1/p' | head -n1)"
  if [[ -n "$TRY_AGAIN_INDEX" ]]; then
    opencli browser click "$TRY_AGAIN_INDEX" >/dev/null
    sleep 1
    STATE_OUTPUT="$(opencli browser state)"
  fi
fi

INPUT_INDEX="$(printf '%s\n' "$STATE_OUTPUT" | sed -n 's/.*\[\([0-9]\+\)\]<input .*type=email.*/\1/p' | head -n1)"
BUTTON_INDEX="$(printf '%s\n' "$STATE_OUTPUT" | sed -n 's/.*\[\([0-9]\+\)\]<button type=submit>Continue with email<.*/\1/p' | head -n1)"

if [[ -z "$INPUT_INDEX" || -z "$BUTTON_INDEX" ]]; then
  echo "Failed to locate Groq email input/button on the page." >&2
  echo "$STATE_OUTPUT" >&2
  exit 1
fi

opencli browser type "$INPUT_INDEX" "$FINAL_EMAIL" >/dev/null
VALUE_OUTPUT="$(opencli browser get value "$INPUT_INDEX")"
ACTUAL_VALUE="$(printf '%s\n' "$VALUE_OUTPUT" | sed -n 's/.*"value": "\(.*\)".*/\1/p' | head -n1)"
if [[ -z "$ACTUAL_VALUE" ]]; then
  ACTUAL_VALUE="$(printf '%s\n' "$VALUE_OUTPUT" | sed -n 's/.*value.:.\(.*\)$/\1/p' | head -n1 | tr -d '"')"
fi
if [[ "$ACTUAL_VALUE" != "$FINAL_EMAIL" ]]; then
  echo "Browser input verification failed. Expected '$FINAL_EMAIL' but found '$ACTUAL_VALUE'" >&2
  echo "$VALUE_OUTPUT" >&2
  exit 1
fi

opencli browser click "$BUTTON_INDEX" >/dev/null
opencli browser wait time "$WAIT_SECONDS" >/dev/null
POST_STATE="$(opencli browser state)"
URL_OUTPUT="$(opencli browser get url)"
CURRENT_URL="$(printf '%s\n' "$URL_OUTPUT" | sed -n 's/.*"url": "\(.*\)".*/\1/p' | head -n1)"
if [[ -z "$CURRENT_URL" ]]; then
  CURRENT_URL="$(printf '%s\n' "$URL_OUTPUT" | sed -n 's/^URL: //p' | head -n1)"
fi
if [[ -z "$CURRENT_URL" ]]; then
  CURRENT_URL="$URL"
fi

STATUS="unknown"
DETAIL=""
if printf '%s' "$POST_STATE" | grep -qi 'Check your email'; then
  STATUS="check-your-email"
  DETAIL="Groq accepted the email and asked to check inbox."
elif printf '%s' "$POST_STATE" | grep -qi 'Email format is invalid'; then
  STATUS="form-error"
  DETAIL="Email format is invalid."
elif printf '%s' "$CURRENT_URL" | grep -qi 'accounts.google.com'; then
  STATUS="unexpected-google-oauth"
  DETAIL="Groq redirected to Google OAuth."
else
  DETAIL="Did not reach a recognized post-submit state."
fi

python3 - <<PY
import csv, json, sys
row = {
  'email': ${FINAL_EMAIL@Q},
  'source': ${SOURCE@Q},
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
