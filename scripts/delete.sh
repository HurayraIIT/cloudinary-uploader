#!/bin/bash
# Permanently Deletes uploaded files from Cloudinary, given their Share Links. Only links in the Cloudinary
# URL's own cloud are accepted. Without --yes it only prints what it would Delete and exits 2.
# Run it only when the user asks for a Delete (docs/adr/0003).
#
# Usage: delete.sh [--yes] <share_link1> [share_link2 ...]
# Prints one line per link: `deleted<TAB><link>`, `already gone<TAB><link>` or `would delete<TAB><kind> <public_id><TAB><link>`.

set -uo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

CONFIRMED=false
LINKS=()
for ARG in "$@"; do
  case "$ARG" in
    --yes) CONFIRMED=true ;;
    -*) echo "Error: unknown option '$ARG'." >&2; exit 1 ;;
    *) LINKS+=("$ARG") ;;
  esac
done

if [ "${#LINKS[@]}" -eq 0 ]; then
  echo "Usage: $0 [--yes] <share_link1> [share_link2 ...]" >&2
  exit 1
fi

cu_require_credentials || exit 1

FAILURE_COUNT=0
_fail() {
  echo "Error: $1" >&2
  FAILURE_COUNT=$((FAILURE_COUNT + 1))
}

for LINK in "${LINKS[@]}"; do
  if ! cu_parse_share_link "$LINK"; then
    _fail "'$LINK' isn't a Cloudinary Share Link. Skipping."
    continue
  fi
  if [ "$CU_LINK_CLOUD" != "$CU_CLOUD_NAME" ]; then
    _fail "'$LINK' belongs to cloud '$CU_LINK_CLOUD', not this account's '$CU_CLOUD_NAME'. Skipping."
    continue
  fi

  if [ "$CONFIRMED" != true ]; then
    printf 'would delete\t%s %s\t%s\n' "$CU_LINK_KIND" "$CU_LINK_PUBLIC_ID" "$LINK"
    continue
  fi

  TIMESTAMP=$(date +%s)
  # invalidate=true purges the CDN cache, so the Share Link stops working within minutes.
  SIGNATURE=$(cu_sign "$CU_API_SECRET" \
    "invalidate=true" \
    "public_id=$CU_LINK_PUBLIC_ID" \
    "timestamp=$TIMESTAMP") || exit 1

  RESPONSE=$(curl -sS --max-time 60 \
    -X POST "https://api.cloudinary.com/v1_1/${CU_CLOUD_NAME}/${CU_LINK_KIND}/destroy" \
    --data-urlencode "api_key=${CU_API_KEY}" \
    --data-urlencode "invalidate=true" \
    --data-urlencode "public_id=${CU_LINK_PUBLIC_ID}" \
    --data-urlencode "timestamp=${TIMESTAMP}" \
    --data-urlencode "signature=${SIGNATURE}" \
    -w $'\n%{http_code}')
  CURL_EXIT=$?
  if [ "$CURL_EXIT" -ne 0 ]; then
    _fail "Network error deleting '$LINK' (curl exit $CURL_EXIT)."
    continue
  fi
  STATUS="${RESPONSE##*$'\n'}"
  BODY="${RESPONSE%$'\n'*}"

  if [ "$STATUS" != 200 ]; then
    MESSAGE=$(cu_json_get "$BODY" error.message)
    _fail "Couldn't delete '$LINK': ${MESSAGE:-unexpected response} (HTTP $STATUS)"
    continue
  fi
  case "$(cu_json_get "$BODY" result)" in
    ok) printf 'deleted\t%s\n' "$LINK" ;;
    "not found") printf 'already gone\t%s\n' "$LINK" ;;
    *) _fail "Couldn't delete '$LINK'. Response: $BODY" ;;
  esac
done

[ "$FAILURE_COUNT" -gt 0 ] && exit 1
[ "$CONFIRMED" = true ] || exit 2
exit 0
