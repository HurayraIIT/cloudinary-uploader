#!/bin/bash
# Uploads one or more files to Cloudinary and prints their direct URLs to stdout.
# All errors are printed to stderr.
# Requires CLOUDINARY_URL (cloudinary://<key>:<secret>@<cloud>) in the environment, ~/.zshrc or ~/.bashrc.

set -uo pipefail

MAX_FILE_BYTES=10485760  # 10 MB

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <file_path1> [file_path2 ...]" >&2
  exit 1
fi

# Resolve CLOUDINARY_URL from the environment, then ~/.zshrc, then ~/.bashrc.
# Never source shell init files (avoids running nvm/rbenv/prompt code).
_load_cloudinary_url() {
  # Already set in environment
  [ -n "${CLOUDINARY_URL:-}" ] && return 0

  # Targeted grep from shell rc files (no sourcing)
  local rc_files=("$HOME/.zshrc" "$HOME/.bashrc")
  for rc in "${rc_files[@]}"; do
    if [ -f "$rc" ]; then
      local line
      line=$(grep -v '^\s*#' "$rc" 2>/dev/null | grep -m1 'CLOUDINARY_URL=')
      if [ -n "$line" ]; then
        # Strip leading whitespace, export keyword and surrounding quotes
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line#export }"
        line="${line#CLOUDINARY_URL=}"
        line="${line%\"}"
        line="${line#\"}"
        line="${line%\'}"
        line="${line#\'}"
        CLOUDINARY_URL="$line"
        [ -n "$CLOUDINARY_URL" ] && return 0
      fi
    fi
  done

  return 1
}

_load_cloudinary_url || true

if [ -z "${CLOUDINARY_URL:-}" ]; then
  echo "Error: CLOUDINARY_URL is not set. Set it in your environment, or add: export CLOUDINARY_URL=cloudinary://<key>:<secret>@<cloud> to ~/.zshrc or ~/.bashrc." >&2
  exit 1
fi

# Validate scheme
if [[ "$CLOUDINARY_URL" != cloudinary://* ]]; then
  echo "Error: CLOUDINARY_URL must start with 'cloudinary://'. Got: ${CLOUDINARY_URL%%:*}://..." >&2
  exit 1
fi

# Parse cloudinary://<API_KEY>:<API_SECRET>@<CLOUD_NAME>
URL_WITHOUT_SCHEME="${CLOUDINARY_URL#cloudinary://}"
API_KEY="${URL_WITHOUT_SCHEME%%:*}"
SECRET_AND_CLOUD="${URL_WITHOUT_SCHEME#*:}"
# Use shortest match from the right so secrets containing '@' are handled correctly
CLOUD_NAME="${SECRET_AND_CLOUD##*@}"
API_SECRET="${SECRET_AND_CLOUD%@*}"

if [ -z "$API_KEY" ] || [ -z "$API_SECRET" ] || [ -z "$CLOUD_NAME" ]; then
  echo "Error: Could not parse CLOUDINARY_URL. Expected format: cloudinary://<key>:<secret>@<cloud>" >&2
  exit 1
fi

# Detect sha1 command
if command -v sha1sum >/dev/null 2>&1; then
  _sha1() { echo -n "$1" | sha1sum | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  _sha1() { echo -n "$1" | shasum | awk '{print $1}'; }
else
  echo "Error: Neither sha1sum nor shasum is available." >&2
  exit 1
fi

# Detect file size command
_file_size() {
  if stat -f%z "$1" 2>/dev/null; then return; fi   # macOS
  stat -c%s "$1" 2>/dev/null                        # Linux
}

API_ENDPOINT="https://api.cloudinary.com/v1_1/${CLOUD_NAME}/auto/upload"
FAILURE_COUNT=0

for FILE_PATH in "$@"; do
  if [ ! -f "$FILE_PATH" ]; then
    echo "Error: File '$FILE_PATH' does not exist. Skipping." >&2
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    continue
  fi

  # File size guard
  FILE_SIZE=$(_file_size "$FILE_PATH")
  if [ -n "$FILE_SIZE" ] && [ "$FILE_SIZE" -gt "$MAX_FILE_BYTES" ]; then
    SIZE_MB=$(( FILE_SIZE / 1048576 ))
    echo "Error: '$FILE_PATH' is ${SIZE_MB}MB, exceeding the 10MB limit. Skipping." >&2
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    continue
  fi

  # Build public_id: YYMMDD_HHMMSS_<sanitised-basename-without-extension>
  BASENAME=$(basename "$FILE_PATH")
  RAW_NAME="${BASENAME%.*}"
  SANITIZED=$(echo "$RAW_NAME" | sed -E 's/[^a-zA-Z0-9_\-]/-/g')
  DATESTAMP=$(date +%y%m%d_%H%M%S)

  if [ -z "$SANITIZED" ]; then
    # Dot-prefixed files (e.g. .gitignore) produce an empty name after stripping extension
    echo "Error: Cannot derive a public_id from '$FILE_PATH' (dot-prefixed filename with no stem). Skipping." >&2
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    continue
  fi

  PUBLIC_ID="${DATESTAMP}_${SANITIZED}"
  TIMESTAMP=$(date +%s)

  # Cloudinary signature: parameters alphabetically sorted, then secret appended (no &)
  STRING_TO_SIGN="public_id=${PUBLIC_ID}&timestamp=${TIMESTAMP}${API_SECRET}"
  SIGNATURE=$(_sha1 "$STRING_TO_SIGN")

  # Perform the upload; capture curl exit code separately from response body
  RESPONSE=$(curl -s --max-time 60 -X POST "$API_ENDPOINT" \
    -F "file=@${FILE_PATH}" \
    -F "api_key=${API_KEY}" \
    -F "public_id=${PUBLIC_ID}" \
    -F "timestamp=${TIMESTAMP}" \
    -F "signature=${SIGNATURE}" 2>&1)
  CURL_EXIT=$?

  if [ $CURL_EXIT -ne 0 ]; then
    echo "Error: Network/connection error uploading '$FILE_PATH' (curl exit $CURL_EXIT)." >&2
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    continue
  fi

  # Parse secure_url from response (jq preferred, python3 fallback, grep last resort)
  SECURE_URL=""
  if command -v jq >/dev/null 2>&1; then
    SECURE_URL=$(echo "$RESPONSE" | jq -r '.secure_url // empty' 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    SECURE_URL=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('secure_url',''))" 2>/dev/null)
  else
    SECURE_URL=$(echo "$RESPONSE" | grep -o '"secure_url" *: *"[^"]*"' | sed 's/.*: *"\(.*\)"/\1/')
  fi

  if [ -z "$SECURE_URL" ]; then
    echo "Error: Upload failed for '$FILE_PATH'. Response: $RESPONSE" >&2
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
  else
    echo "$SECURE_URL"
  fi
done

[ "$FAILURE_COUNT" -gt 0 ] && exit 1
exit 0
