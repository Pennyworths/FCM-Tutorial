#!/usr/bin/env sh
set -euo pipefail

echo "[INFO] Loading env vars..."
API_BASE_URL="${API_BASE_URL:-}"
TEST_USER_ID="${TEST_USER_ID:-debug-user-2}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-30}"

if [ -z "$API_BASE_URL" ]; then
  echo "[ERROR] API_BASE_URL is not set"
  exit 1
fi

API_BASE_URL="${API_BASE_URL%/}"

# 1. generate nonce（UUID）
if [ -r /proc/sys/kernel/random/uuid ]; then
  NONCE="$(cat /proc/sys/kernel/random/uuid)"
else
  NONCE="$(date +%s)-$RANDOM"
fi

echo "[INFO] Using nonce = $NONCE"

SEND_URL="${API_BASE_URL}/messages/send"

# 2.  POST /messages/send
echo "[INFO] POST $SEND_URL"

JSON_PAYLOAD=$(cat <<EOF
{
  "user_id": "$TEST_USER_ID",
  "title": "FCM E2E Test",
  "body": "Test message",
  "data": {
    "type": "e2e_test",
    "nonce": "$NONCE"
  }
}
EOF
)

echo "[DEBUG] Payload: $JSON_PAYLOAD"

SEND_RESP=$(curl -sS -w "\n%{http_code}" -X POST "$SEND_URL" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" )

# extract body and status code
SEND_BODY="$(printf '%s\n' "$SEND_RESP" | head -n -1)"
SEND_CODE="$(printf '%s\n' "$SEND_RESP" | tail -n 1)"

echo "[INFO] /messages/send HTTP $SEND_CODE, body=$SEND_BODY"

if [ "$SEND_CODE" -ge 400 ]; then
  echo "[ERROR] /messages/send returned error"
  exit 1
fi

# 3. poll GET /test/status?nonce={nonce}
STATUS_URL="${API_BASE_URL}/test/status"
DEADLINE=$(( $(date +%s) + TIMEOUT_SECONDS ))

echo "[INFO] Start polling $STATUS_URL?nonce=$NONCE for up to ${TIMEOUT_SECONDS}s"

while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  RESP=$(curl -sS -w "\n%{http_code}" "$STATUS_URL?nonce=$NONCE" || true)

  BODY="$(printf '%s\n' "$RESP" | head -n -1)"
  CODE="$(printf '%s\n' "$RESP" | tail -n 1)"

  echo "[DEBUG] GET $STATUS_URL?nonce=$NONCE -> HTTP $CODE, body=$BODY"

  if [ "$CODE" -eq 200 ]; then
    # extract status field with jq, if jq is not installed, simple string matching
    if command -v jq >/dev/null 2>&1; then
      STATUS=$(printf '%s' "$BODY" | jq -r '.status // .Status // ""' | tr '[:lower:]' '[:upper:]')
    else
      # non-strict: simple find "ACKED"
      echo "$BODY" | grep -qi "ACKED" && STATUS="ACKED" || STATUS=""
    fi

    if [ "$STATUS" = "ACKED" ]; then
      echo "[SUCCESS] Status became ACKED 🎉"
      exit 0
    fi
  fi

  sleep 2
done

echo "[ERROR] TIMEOUT waiting for status=ACKED"
exit 2
