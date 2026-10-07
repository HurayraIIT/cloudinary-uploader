#!/bin/bash
# Uploads one or more files to Cloudinary. For each success it prints one line to stdout:
#   <kind><TAB><path as given><TAB><Share Link>
# where kind is image, video or raw. Errors and notes go to stderr; exits non-zero if any file fails.
# Requires CLOUDINARY_URL (cloudinary://<key>:<secret>@<cloud>) in the environment, ~/.zshrc or ~/.bashrc.

set -uo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <file_path1> [file_path2 ...]" >&2
  exit 1
fi

cu_require_credentials || exit 1

FAILURE_COUNT=0
RESTRICTED_LINKS=()

_fail() {
  echo "Error: $1" >&2
  FAILURE_COUNT=$((FAILURE_COUNT + 1))
}

_file_size() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null
}

for FILE_PATH in "$@"; do
  if [ ! -f "$FILE_PATH" ]; then
    _fail "'$FILE_PATH' does not exist or isn't a regular file. Skipping."
    continue
  fi
  if [ ! -r "$FILE_PATH" ]; then
    _fail "'$FILE_PATH' isn't readable. Skipping."
    continue
  fi

  FILE_SIZE=$(_file_size "$FILE_PATH")
  if [ -z "$FILE_SIZE" ]; then
    _fail "Couldn't read the size of '$FILE_PATH'. Skipping."
    continue
  fi
  if [ "$FILE_SIZE" -gt "$CU_MAX_FILE_BYTES" ]; then
    _fail "'$FILE_PATH' is $((FILE_SIZE / 1048576)) MB, over Cloudinary's 100 MB limit for a single upload. Skipping."
    continue
  fi

  FILENAME=$(basename "$FILE_PATH")
  EXTENSION=$(cu_extension "$FILE_PATH")
  KIND=$(cu_kind "$FILE_PATH")
  NAME=$(cu_random_name)
  if [ "${#NAME}" -ne "$CU_NAME_LENGTH" ]; then
    _fail "Couldn't generate a random name for '$FILE_PATH'. Skipping."
    continue
  fi
  PUBLIC_ID=$(cu_public_id "$KIND" "$NAME" "$EXTENSION")
  TIMESTAMP=$(date +%s)

  # Never overwrite: a Share Link has no version, so a reused name would change what an older link serves.
  SIGNATURE=$(cu_sign "$CU_API_SECRET" \
    "asset_folder=$CU_ASSET_FOLDER" \
    "display_name=$FILENAME" \
    "overwrite=false" \
    "public_id=$PUBLIC_ID" \
    "timestamp=$TIMESTAMP") || exit 1

  # Quote the path for curl's -F syntax, so `;` or `,` in a filename isn't read as a field option.
  QUOTED_PATH="${FILE_PATH//\\/\\\\}"
  QUOTED_PATH="${QUOTED_PATH//\"/\\\"}"

  # --speed-time aborts a stalled upload without capping a slow but healthy one.
  RESPONSE=$(curl -sS --connect-timeout 20 --speed-limit 1 --speed-time 60 \
    -X POST "https://api.cloudinary.com/v1_1/${CU_CLOUD_NAME}/${KIND}/upload" \
    -F "file=@\"${QUOTED_PATH}\"" \
    --form-string "api_key=${CU_API_KEY}" \
    --form-string "asset_folder=${CU_ASSET_FOLDER}" \
    --form-string "display_name=${FILENAME}" \
    --form-string "overwrite=false" \
    --form-string "public_id=${PUBLIC_ID}" \
    --form-string "timestamp=${TIMESTAMP}" \
    --form-string "signature=${SIGNATURE}" \
    -w $'\n%{http_code}')
  CURL_EXIT=$?
  if [ "$CURL_EXIT" -ne 0 ]; then
    _fail "Network error uploading '$FILE_PATH' (curl exit $CURL_EXIT)."
    continue
  fi
  STATUS="${RESPONSE##*$'\n'}"
  BODY="${RESPONSE%$'\n'*}"

  if [ "$STATUS" != 200 ]; then
    MESSAGE=$(cu_json_get "$BODY" error.message)
    _fail "Upload failed for '$FILE_PATH': ${MESSAGE:-unexpected response} (HTTP $STATUS)"
    continue
  fi
  # With overwrite=false, a taken name still answers 200, describing the *old* file.
  if [ "$(cu_json_get "$BODY" existing)" = true ]; then
    _fail "Upload failed for '$FILE_PATH': the name $PUBLIC_ID is already taken. Try again."
    continue
  fi

  STORED_ID=$(cu_json_get "$BODY" public_id)
  FORMAT=$(cu_json_get "$BODY" format)
  if [ -z "$STORED_ID" ] || { [ "$KIND" != raw ] && [ -z "$FORMAT" ]; }; then
    _fail "Upload of '$FILE_PATH' answered without a public_id or format. Response: $BODY"
    continue
  fi

  LINK=$(cu_share_link "$CU_CLOUD_NAME" "$KIND" "$STORED_ID" "$FORMAT")
  printf '%s\t%s\t%s\n' "$KIND" "$FILE_PATH" "$LINK"
  if cu_delivery_restricted "$FILE_PATH"; then
    RESTRICTED_LINKS+=("$LINK")
  fi
done

if [ "${#RESTRICTED_LINKS[@]}" -gt 0 ]; then
  echo "Note: Cloudinary's Free plan blocks PDF and archive links with HTTP 401 until \"Allow delivery of PDF and ZIP files\" is turned on in Settings → Security (https://console.cloudinary.com/app/settings/security). Affected: ${RESTRICTED_LINKS[*]}" >&2
fi

[ "$FAILURE_COUNT" -gt 0 ] && exit 1
exit 0
