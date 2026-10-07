#!/bin/bash
# Offline tests for scripts/lib.sh and the scripts' argument handling. Never touches the network.
# Usage: tests/run.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/scripts"
# shellcheck source=../scripts/lib.sh
. "$SCRIPTS/lib.sh"

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

PASSED=0
FAILED=0

expect() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$name" "$expected" "$actual"
  fi
}

# --- cu_rc_value ---

rc() { printf '%s\n' "$@" >"$SCRATCH/rc"; cu_rc_value "$SCRATCH/rc"; }

expect "rc: export with double quotes" "cloudinary://k:s@c" "$(rc 'export CLOUDINARY_URL="cloudinary://k:s@c"')"
expect "rc: single quotes" "cloudinary://k:s@c" "$(rc "CLOUDINARY_URL='cloudinary://k:s@c'")"
expect "rc: indented, unquoted" "cloudinary://k:s@c" "$(rc '   export   CLOUDINARY_URL=cloudinary://k:s@c')"
expect "rc: the last assignment wins, as in the shell" "cloudinary://new:s@c" \
  "$(rc 'export CLOUDINARY_URL=cloudinary://old:s@c' 'export CLOUDINARY_URL=cloudinary://new:s@c')"
expect "rc: commented lines are ignored" "cloudinary://k:s@c" \
  "$(rc 'export CLOUDINARY_URL=cloudinary://k:s@c' '# export CLOUDINARY_URL=cloudinary://commented:s@c')"
expect "rc: other variables ending in CLOUDINARY_URL are ignored" "cloudinary://k:s@c" \
  "$(rc 'export CLOUDINARY_URL=cloudinary://k:s@c' 'export MY_CLOUDINARY_URL=cloudinary://other:s@c')"
expect "rc: a trailing comment is stripped" "cloudinary://k:s@c" "$(rc 'export CLOUDINARY_URL=cloudinary://k:s@c  # work account')"
expect "rc: a # inside quotes is kept" "cloudinary://k:s#1@c" "$(rc 'export CLOUDINARY_URL="cloudinary://k:s#1@c" # note')"
rc 'export OTHER=1' >/dev/null; expect "rc: no assignment fails" 1 "$?"
cu_rc_value "$SCRATCH/missing" >/dev/null; expect "rc: a missing file fails" 1 "$?"

# --- cu_load_cloudinary_url ---

mkdir -p "$SCRATCH/home"
printf 'export CLOUDINARY_URL=cloudinary://bash:s@c\n' >"$SCRATCH/home/.bashrc"
expect "load: falls back to ~/.bashrc" "cloudinary://bash:s@c|~/.bashrc" \
  "$(unset CLOUDINARY_URL; HOME="$SCRATCH/home"; cu_load_cloudinary_url; echo "$CLOUDINARY_URL|$CU_URL_SOURCE")"
printf 'export CLOUDINARY_URL=cloudinary://zsh:s@c\n' >"$SCRATCH/home/.zshrc"
expect "load: ~/.zshrc before ~/.bashrc" "cloudinary://zsh:s@c|~/.zshrc" \
  "$(unset CLOUDINARY_URL; HOME="$SCRATCH/home"; cu_load_cloudinary_url; echo "$CLOUDINARY_URL|$CU_URL_SOURCE")"
expect "load: the environment wins" "cloudinary://env:s@c|the environment" \
  "$(CLOUDINARY_URL=cloudinary://env:s@c; HOME="$SCRATCH/home"; cu_load_cloudinary_url; echo "$CLOUDINARY_URL|$CU_URL_SOURCE")"

# --- cu_parse_cloudinary_url ---

parse() { cu_parse_cloudinary_url "$1" && echo "$CU_API_KEY|$CU_API_SECRET|$CU_CLOUD_NAME"; }

expect "parse: plain" "123|abc|demo" "$(parse 'cloudinary://123:abc@demo')"
expect "parse: a whole rc line" "123|abc|demo" "$(parse '  export CLOUDINARY_URL="cloudinary://123:abc@demo" ')"
expect "parse: a query is dropped" "123|abc|demo" "$(parse 'cloudinary://123:abc@demo?secure=true')"
expect "parse: @ in the secret" "123|a@b|demo" "$(parse 'cloudinary://123:a@b@demo')"
expect "parse: : in the secret" "123|a:b|demo" "$(parse 'cloudinary://123:a:b@demo')"
parse 'https://123:abc@demo' >/dev/null; expect "parse: wrong scheme fails" 1 "$?"
parse 'cloudinary://123abc@demo' >/dev/null; expect "parse: no secret fails" 1 "$?"
parse 'cloudinary://123:abc' >/dev/null; expect "parse: no cloud fails" 1 "$?"
parse 'cloudinary://123:a c@demo' >/dev/null; expect "parse: whitespace fails" 1 "$?"

# --- cu_sign ---

expect "sign: Cloudinary's documented example" "bfd09f95f331f558cbd1320e67aa8d488770583e" \
  "$(cu_sign abcd "timestamp=1315060510" "public_id=sample_image" "eager=w_400,h_300,c_pad|w_260,h_200,c_crop")"
expect "sign: argument order doesn't matter" \
  "$(cu_sign s "a=1" "b=2" "c=3")" "$(cu_sign s "c=3" "a=1" "b=2")"

# --- Kinds and names ---

expect "extension: lowercased" "png" "$(cu_extension /tmp/Shot.PNG)"
expect "extension: last one" "gz" "$(cu_extension logs.tar.gz)"
expect "extension: none" "" "$(cu_extension /tmp/Makefile)"
expect "extension: dot file has none" "" "$(cu_extension /tmp/.env)"
expect "extension: dot file with one" "bak" "$(cu_extension /tmp/.env.bak)"

expect "kind: image MIME" image "$(cu_kind_for image/png png)"
expect "kind: PDF is an image" image "$(cu_kind_for application/pdf pdf)"
expect "kind: video MIME" video "$(cu_kind_for video/quicktime mov)"
expect "kind: audio is a video" video "$(cu_kind_for audio/mpeg mp3)"
expect "kind: text is raw" raw "$(cu_kind_for text/plain log)"
expect "kind: zip is raw" raw "$(cu_kind_for application/zip zip)"
expect "kind: unknown MIME falls back to the extension" image "$(cu_kind_for application/octet-stream heic)"
expect "kind: no MIME, no extension" raw "$(cu_kind_for "" "")"

if command -v file >/dev/null 2>&1; then
  printf '\x89PNG\r\n\x1a\n\0\0\0\rIHDR\0\0\0\x01\0\0\0\x01\x08\x06\0\0\0\x1f\x15\xc4\x89\0\0\0\rIDATx\x9cc\xf8\x0f\0\x01\x01\x01\0\x18\xdd\x8d\xb0\0\0\0\0IEND\xaeB`\x82' >"$SCRATCH/pixel.dat"
  expect "kind: PNG bytes with the wrong extension" image "$(cu_kind "$SCRATCH/pixel.dat")"
  printf 'hello\n' >"$SCRATCH/notes.log"
  expect "kind: a log file" raw "$(cu_kind "$SCRATCH/notes.log")"
fi

NAME=$(cu_random_name)
expect "random name: 8 of a-z0-9" yes "$([[ "$NAME" =~ ^[a-z0-9]{8}$ ]] && echo yes || echo "no ($NAME)")"
expect "random names differ" yes "$([ "$(cu_random_name)" != "$(cu_random_name)" ] && echo yes)"

expect "public_id: image" "d/k3f9x2ab" "$(cu_public_id image k3f9x2ab png)"
expect "public_id: raw keeps its extension" "d/k3f9x2ab.log" "$(cu_public_id raw k3f9x2ab log)"
expect "public_id: raw without an extension" "d/k3f9x2ab" "$(cu_public_id raw k3f9x2ab "")"

# --- Share Links ---

expect "link: image uses the root path" "https://res.cloudinary.com/demo/d/k3f9x2ab.png" "$(cu_share_link demo image d/k3f9x2ab png)"
expect "link: HEIC is delivered as JPEG" "https://res.cloudinary.com/demo/d/k3f9x2ab.jpg" "$(cu_share_link demo image d/k3f9x2ab HEIC)"
expect "link: HEIF too" "https://res.cloudinary.com/demo/d/k3f9x2ab.jpg" "$(cu_share_link demo image d/k3f9x2ab heif)"
expect "link: video" "https://res.cloudinary.com/demo/video/upload/d/k3f9x2ab.mp4" "$(cu_share_link demo video d/k3f9x2ab mp4)"
expect "link: raw" "https://res.cloudinary.com/demo/raw/upload/d/k3f9x2ab.log" "$(cu_share_link demo raw d/k3f9x2ab.log "")"

link() { cu_parse_share_link "$1" && echo "$CU_LINK_CLOUD|$CU_LINK_KIND|$CU_LINK_PUBLIC_ID"; }

expect "read link: root path image" "demo|image|d/k3f9x2ab" "$(link https://res.cloudinary.com/demo/d/k3f9x2ab.png)"
expect "read link: HEIC delivered as JPEG" "demo|image|d/k3f9x2ab" "$(link https://res.cloudinary.com/demo/d/k3f9x2ab.jpg)"
expect "read link: video" "demo|video|d/k3f9x2ab" "$(link https://res.cloudinary.com/demo/video/upload/d/k3f9x2ab.mp4)"
expect "read link: raw keeps its extension" "demo|raw|d/k3f9x2ab.log" "$(link https://res.cloudinary.com/demo/raw/upload/d/k3f9x2ab.log)"
expect "read link: an old versioned secure_url" "demo|image|251008_143012_bug-report" \
  "$(link https://res.cloudinary.com/demo/image/upload/v1759912345/251008_143012_bug-report.png)"
expect "read link: CloudDrop's older shape" "demo|video|clouddrop/260929_101500_rec" \
  "$(link https://res.cloudinary.com/demo/video/upload/v1/clouddrop/260929_101500_rec.mov)"
expect "read link: query and fragment dropped" "demo|image|d/k3f9x2ab" "$(link 'https://res.cloudinary.com/demo/d/k3f9x2ab.png?x=1#y')"
expect "read link: percent-encoding decoded" "demo|image|clouddrop/my shot" "$(link https://res.cloudinary.com/demo/image/upload/clouddrop/my%20shot.png)"
link https://example.com/demo/d/k3f9x2ab.png >/dev/null; expect "read link: another host fails" 1 "$?"
link https://res.cloudinary.com/demo/image/private/s--x--/d/a.png >/dev/null; expect "read link: private delivery fails" 1 "$?"
link https://res.cloudinary.com/demo >/dev/null; expect "read link: no public_id fails" 1 "$?"

cu_delivery_restricted report.PDF; expect "restricted: PDF" 0 "$?"
cu_delivery_restricted logs.tar.gz; expect "restricted: tar.gz" 0 "$?"
cu_delivery_restricted shot.png; expect "restricted: PNG isn't" 1 "$?"

# --- cu_json_get ---

UPLOADED='{"public_id":"d/k3f9x2ab","format":"png","resource_type":"image","existing":false,"secure_url":"https:\/\/res.cloudinary.com\/demo\/image\/upload\/v1\/d\/k3f9x2ab.png"}'
TAKEN='{"public_id":"d/k3f9x2ab","existing":true}'
FAILED_JSON='{"error":{"message":"File size too large. Got 20971520. Maximum is 10485760."}}'
for TOOL in jq python3 grep; do
  if [ "$TOOL" != grep ] && ! command -v "$TOOL" >/dev/null 2>&1; then continue; fi
  expect "json ($TOOL): string" "d/k3f9x2ab" "$(CU_JSON_TOOL=$TOOL cu_json_get "$UPLOADED" public_id)"
  expect "json ($TOOL): false" "false" "$(CU_JSON_TOOL=$TOOL cu_json_get "$UPLOADED" existing)"
  expect "json ($TOOL): true" "true" "$(CU_JSON_TOOL=$TOOL cu_json_get "$TAKEN" existing)"
  expect "json ($TOOL): escaped slashes" "https://res.cloudinary.com/demo/image/upload/v1/d/k3f9x2ab.png" \
    "$(CU_JSON_TOOL=$TOOL cu_json_get "$UPLOADED" secure_url)"
  expect "json ($TOOL): nested" "File size too large. Got 20971520. Maximum is 10485760." \
    "$(CU_JSON_TOOL=$TOOL cu_json_get "$FAILED_JSON" error.message)"
  expect "json ($TOOL): missing" "" "$(CU_JSON_TOOL=$TOOL cu_json_get "$TAKEN" format)"
  expect "json ($TOOL): not JSON" "" "$(CU_JSON_TOOL=$TOOL cu_json_get "<html>502</html>" error.message)"
done

# --- The scripts, without reaching the network ---

FAKE="cloudinary://1:2@demo"

OUT=$(CLOUDINARY_URL=$FAKE "$SCRIPTS/upload.sh" 2>&1); expect "upload: no arguments" 1 "$?"
OUT=$(CLOUDINARY_URL=$FAKE "$SCRIPTS/upload.sh" "$SCRATCH/nope.png" 2>&1)
expect "upload: a missing file fails" 1 "$?"
expect "upload: names the missing file" yes "$([[ "$OUT" == *"nope.png"* ]] && echo yes)"
OUT=$(CLOUDINARY_URL="not-a-secret-value" "$SCRIPTS/upload.sh" "$SCRATCH/notes.log" 2>&1)
expect "upload: a bad Cloudinary URL fails" 1 "$?"
expect "upload: never echoes the Cloudinary URL" yes "$([[ "$OUT" != *"not-a-secret-value"* ]] && echo yes)"
dd if=/dev/zero of="$SCRATCH/huge.mp4" bs=1 count=0 seek=104857601 2>/dev/null
OUT=$(CLOUDINARY_URL=$FAKE "$SCRIPTS/upload.sh" "$SCRATCH/huge.mp4" 2>&1)
expect "upload: over 100 MB is refused" 1 "$?"
expect "upload: says why" yes "$([[ "$OUT" == *"100 MB"* ]] && echo yes)"

OUT=$(CLOUDINARY_URL=$FAKE "$SCRIPTS/delete.sh" 2>&1); expect "delete: no arguments" 1 "$?"
OUT=$(CLOUDINARY_URL=$FAKE "$SCRIPTS/delete.sh" https://res.cloudinary.com/demo/raw/upload/d/k3f9x2ab.log)
expect "delete: without --yes it's a dry run" 2 "$?"
expect "delete: the dry run says what it would Delete" \
  "$(printf 'would delete\traw d/k3f9x2ab.log\thttps://res.cloudinary.com/demo/raw/upload/d/k3f9x2ab.log')" "$OUT"
OUT=$(CLOUDINARY_URL=$FAKE "$SCRIPTS/delete.sh" --yes https://res.cloudinary.com/someone-else/d/k3f9x2ab.png 2>&1)
expect "delete: another cloud is refused" 1 "$?"
expect "delete: names the other cloud" yes "$([[ "$OUT" == *"someone-else"* ]] && echo yes)"
OUT=$(CLOUDINARY_URL=$FAKE "$SCRIPTS/delete.sh" --yes https://example.com/x.png 2>&1)
expect "delete: a non-Cloudinary link is refused" 1 "$?"
OUT=$(CLOUDINARY_URL=$FAKE "$SCRIPTS/delete.sh" --force https://res.cloudinary.com/demo/d/a.png 2>&1)
expect "delete: unknown options are refused" 1 "$?"

echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ] && [ "$PASSED" -gt 0 ]
