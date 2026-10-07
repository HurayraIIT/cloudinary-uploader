#!/bin/bash
# Shared functions for upload.sh and delete.sh. Pure functions (no network) are covered by tests/run.sh.
# Written for bash 3.2, the version macOS ships as /bin/bash.

# Share Links use CloudDrop's shape (docs/adr/0001): a random name in the `d/` URL folder, filed under the
# `clouddrop` console folder.
CU_URL_FOLDER="d"
CU_ASSET_FOLDER="clouddrop"
CU_NAME_LENGTH=8
# Cloudinary refuses single requests over 100 MB, and chunked uploads are out of scope (docs/adr/0002).
CU_MAX_FILE_BYTES=104857600

# --- Cloudinary URL ---------------------------------------------------------------------------------

# Prints the value of the last `CLOUDINARY_URL=` assignment in a shell rc file, the one the shell would use.
# Commented lines are ignored, and so is a trailing `# comment` after an unquoted value. Nothing is sourced.
cu_rc_value() {
  local file="$1" line value
  [ -f "$file" ] || return 1
  line=$(grep -E '^[[:space:]]*(export[[:space:]]+)?CLOUDINARY_URL=' "$file" 2>/dev/null | tail -n 1)
  [ -n "$line" ] || return 1
  value="${line#*CLOUDINARY_URL=}"
  case "$value" in
    \"*) value="${value#\"}"; value="${value%%\"*}" ;;
    \'*) value="${value#\'}"; value="${value%%\'*}" ;;
    *)
      value=$(printf '%s' "$value" | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//')
      ;;
  esac
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

# Sets CLOUDINARY_URL and CU_URL_SOURCE from the environment, then ~/.zshrc, then ~/.bashrc.
cu_load_cloudinary_url() {
  if [ -n "${CLOUDINARY_URL:-}" ]; then
    CU_URL_SOURCE="the environment"
    return 0
  fi
  local rc value
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if value=$(cu_rc_value "$rc"); then
      CLOUDINARY_URL="$value"
      CU_URL_SOURCE="~${rc#"$HOME"}"
      return 0
    fi
  done
  return 1
}

# Splits a Cloudinary URL into CU_API_KEY, CU_API_SECRET and CU_CLOUD_NAME. Tolerates `export`,
# `CLOUDINARY_URL=`, surrounding quotes and whitespace, and a trailing `?query` or `/path`.
cu_parse_cloudinary_url() {
  local text="$1" rest userinfo cloud key secret
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  case "$text" in export\ *) text="${text#export }"; text="${text#"${text%%[![:space:]]*}"}" ;; esac
  text="${text#CLOUDINARY_URL=}"
  text="${text#[\"\']}"
  text="${text%[\"\']}"

  case "$text" in cloudinary://*) ;; *) return 1 ;; esac
  rest="${text#cloudinary://}"
  case "$rest" in *@*) ;; *) return 1 ;; esac
  userinfo="${rest%@*}"
  cloud="${rest##*@}"
  cloud="${cloud%%[?/]*}"
  case "$userinfo" in *:*) ;; *) return 1 ;; esac
  key="${userinfo%%:*}"
  secret="${userinfo#*:}"

  [ -n "$key" ] && [ -n "$secret" ] && [ -n "$cloud" ] || return 1
  case "$key$secret$cloud" in *[[:space:]]*) return 1 ;; esac
  CU_API_KEY="$key"
  CU_API_SECRET="$secret"
  CU_CLOUD_NAME="$cloud"
}

# Loads and parses the Cloudinary URL, or explains on stderr what's wrong without ever printing it.
cu_require_credentials() {
  if ! cu_load_cloudinary_url; then
    echo "Error: CLOUDINARY_URL is not set. Set it in your environment, or add: export CLOUDINARY_URL=cloudinary://<key>:<secret>@<cloud> to ~/.zshrc or ~/.bashrc." >&2
    return 1
  fi
  if ! cu_parse_cloudinary_url "$CLOUDINARY_URL"; then
    echo "Error: CLOUDINARY_URL from $CU_URL_SOURCE isn't a Cloudinary URL. It must look like cloudinary://<key>:<secret>@<cloud>." >&2
    return 1
  fi
}

# --- Signing ----------------------------------------------------------------------------------------

cu_sha1() {
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha1sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 1 | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    printf '%s' "$1" | openssl sha1 | awk '{print $NF}'
  else
    echo "Error: none of sha1sum, shasum or openssl is available." >&2
    return 1
  fi
}

# Cloudinary's signature: the `key=value` pairs sorted by key and joined with `&`, then the secret appended,
# SHA-1 hashed. Usage: cu_sign <secret> key=value...
cu_sign() {
  local secret="$1"; shift
  local joined
  joined=$(printf '%s\n' "$@" | LC_ALL=C sort | paste -sd '&' -)
  cu_sha1 "${joined}${secret}"
}

# --- Kinds and names --------------------------------------------------------------------------------

cu_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# The file's extension, lowercased, or nothing. A dot-prefixed name such as `.env` has no extension.
cu_extension() {
  local base="${1##*/}"
  base="${base#.}"
  case "$base" in *.*) cu_lower "${base##*.}" ;; esac
}

# The Kind for a MIME type, with the extension as a fallback when `file` can't tell:
# image (PDFs included), video (audio included) or raw.
cu_kind_for() {
  local mime="$1" ext="$2"
  case "$mime" in
    image/*|application/pdf) echo image; return ;;
    video/*|audio/*) echo video; return ;;
  esac
  case "$ext" in
    jpg|jpeg|png|gif|webp|avif|heic|heif|bmp|tif|tiff|ico|svg|pdf|psd) echo image ;;
    mp4|mov|m4v|webm|mkv|avi|mp3|m4a|wav|flac|ogg|aac) echo video ;;
    *) echo raw ;;
  esac
}

cu_kind() {
  local mime=""
  command -v file >/dev/null 2>&1 && mime=$(file --mime-type -b "$1" 2>/dev/null)
  cu_kind_for "$mime" "$(cu_extension "$1")"
}

cu_random_name() {
  local name
  name=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c "$CU_NAME_LENGTH")
  printf '%s\n' "$name"
}

# The public_id for an Upload. Raw files must carry their extension, or their Share Link has none;
# images and videos must not, since Cloudinary adds the format itself.
cu_public_id() {
  local kind="$1" name="$2" ext="$3"
  if [ "$kind" = raw ] && [ -n "$ext" ]; then
    printf '%s/%s.%s\n' "$CU_URL_FOLDER" "$name" "$ext"
  else
    printf '%s/%s\n' "$CU_URL_FOLDER" "$name"
  fi
}

# --- Share Links ------------------------------------------------------------------------------------

# Built from what Cloudinary stored, not its `secure_url` (docs/adr/0001): no version, and images use the
# root path form, which only works for images. HEIC/HEIF is delivered as JPEG so every browser shows it.
cu_share_link() {
  local cloud="$1" kind="$2" public_id="$3" format
  format=$(cu_lower "$4")
  case "$kind" in
    image)
      case "$format" in heic|heif) format=jpg ;; esac
      printf 'https://res.cloudinary.com/%s/%s.%s\n' "$cloud" "$public_id" "$format" ;;
    video) printf 'https://res.cloudinary.com/%s/video/upload/%s.%s\n' "$cloud" "$public_id" "$format" ;;
    raw) printf 'https://res.cloudinary.com/%s/raw/upload/%s\n' "$cloud" "$public_id" ;;
  esac
}

cu_percent_decode() {
  printf '%b' "${1//%/\\x}"
}

# Reads a Share Link, or any Cloudinary delivery URL without transformations, into CU_LINK_CLOUD,
# CU_LINK_KIND and CU_LINK_PUBLIC_ID. Raw public_ids keep their extension; the others lose it.
cu_parse_share_link() {
  local link="$1" path cloud kind rest
  link="${link%%[?#]*}"
  case "$link" in
    https://res.cloudinary.com/*) path="${link#https://res.cloudinary.com/}" ;;
    http://res.cloudinary.com/*) path="${link#http://res.cloudinary.com/}" ;;
    *) return 1 ;;
  esac
  cloud="${path%%/*}"
  rest="${path#*/}"
  [ -n "$cloud" ] && [ "$rest" != "$path" ] && [ -n "$rest" ] || return 1

  case "$rest" in
    image/upload/*|video/upload/*|raw/upload/*)
      kind="${rest%%/*}"
      rest="${rest#*/upload/}"
      ;;
    image/*|video/*|raw/*) return 1 ;;  # private, authenticated or fetched delivery types
    *) kind=image ;;                   # root path form
  esac
  # An old `secure_url` has a version segment.
  if [[ "$rest" =~ ^v[0-9]+/ ]]; then rest="${rest#*/}"; fi
  rest=$(cu_percent_decode "$rest")
  if [ "$kind" != raw ]; then
    case "${rest##*/}" in *.*) rest="${rest%.*}" ;; esac
  fi
  [ -n "$rest" ] || return 1

  CU_LINK_CLOUD="$cloud"
  CU_LINK_KIND="$kind"
  CU_LINK_PUBLIC_ID="$rest"
}

# PDFs and archives answer 401 on Free plans until "Allow delivery of PDF and ZIP files" is turned on.
cu_delivery_restricted() {
  case "$(cu_extension "$1")" in pdf|zip|rar|tgz|gz|bz2|bzip|7z) return 0 ;; esac
  return 1
}

# --- Responses --------------------------------------------------------------------------------------

# Prints a field of a JSON object, such as `public_id` or `error.message`, or nothing.
# Uses jq, then python3, then a grep that's good enough for Cloudinary's flat answers.
# CU_JSON_TOOL forces one of them (for tests).
cu_json_get() {
  local json="$1" path="$2" tool="${CU_JSON_TOOL:-}"
  if [ -z "$tool" ]; then
    if command -v jq >/dev/null 2>&1; then tool=jq
    elif command -v python3 >/dev/null 2>&1; then tool=python3
    else tool=grep
    fi
  fi
  case "$tool" in
    jq) printf '%s' "$json" | jq -r --arg path "$path" 'getpath($path | split(".")) | select(. != null) | tostring' 2>/dev/null ;;
    python3)
      printf '%s' "$json" | python3 -c '
import json, sys
try:
    value = json.load(sys.stdin)
    for key in sys.argv[1].split("."):
        value = value[key]
except Exception:
    sys.exit(0)
if value is not None:
    print(json.dumps(value) if isinstance(value, bool) else value)
' "$path" 2>/dev/null ;;
    grep)
      printf '%s' "$json" \
        | grep -oE "\"${path##*.}\" *: *(\"([^\"\\\\]|\\\\.)*\"|true|false|-?[0-9.]+)" \
        | head -n 1 \
        | sed -E 's/^"[^"]*" *: *//; s/^"(.*)"$/\1/; s#\\/#/#g; s/\\"/"/g' ;;
  esac
}
