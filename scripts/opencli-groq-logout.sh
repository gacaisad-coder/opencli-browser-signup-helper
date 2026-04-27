#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/opencli-groq-logout.sh [--url https://console.groq.com/home]

What it does:
- opens Groq in the browser bridge
- clicks the visible Sign Out button
- reports the resulting state

Notes:
- This helper expects an already logged-in Groq session.
- It uses the proven browser click flow instead of page.evaluate() for interaction.
EOF
}

need_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required binary: $1" >&2
    exit 1
  }
}

URL="https://console.groq.com/home"
FORMAT="table"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="${2:-}"
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

opencli browser open "$URL" >/dev/null
opencli browser wait time 3 >/dev/null
STATE_OUTPUT="$(opencli browser state)"

SIGN_OUT_INDEX="$(printf '%s\n' "$STATE_OUTPUT" | sed -n '/Sign Out/ s/.*\[\([0-9]\+\)\]<button>.*/\1/p' | head -n1)"
if [[ -z "$SIGN_OUT_INDEX" ]]; then
  echo "Failed to locate the Sign Out button on the Groq page." >&2
  echo "$STATE_OUTPUT" >&2
  exit 1
fi

opencli browser click "$SIGN_OUT_INDEX" >/dev/null
opencli browser wait time 3 >/dev/null
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
if printf '%s' "$POST_STATE" | grep -qi 'Sign in\|Log in\|Looks like there was an error!'; then
  STATUS="signed-out"
  DETAIL="Groq logout flow completed and the browser is no longer on an authenticated state."
elif printf '%s' "$CURRENT_URL" | grep -qi '/authenticate\|/home'; then
  STATUS="clicked"
  DETAIL="Sign Out button was clicked; verify the browser session if you need a stricter confirmation."
else
  DETAIL="The resulting state was not recognized after clicking Sign Out."
fi

python3 - <<PY
import csv, json, sys
row = {
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
