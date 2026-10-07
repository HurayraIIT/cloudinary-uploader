---
name: cloudinary-uploader
description: >
  Upload local images, videos, and files to Cloudinary and return a short public Share Link, or
  Delete an uploaded file when the user asks. Use when the user wants to share a local screenshot,
  image, video, recording, log, or other file via a public hosted link — including when preparing
  visual evidence for GitHub issues, documentation, or chat messages. Also use for batch-uploading
  multiple local assets. Triggers even when the user doesn't say "Cloudinary" explicitly but wants a
  hosted public URL for a local file.
license: MIT
compatibility: Requires bash, curl and file (jq or python3 optional) and a CLOUDINARY_URL. macOS and Linux.
allowed-tools: Bash("${CLAUDE_SKILL_DIR}/scripts/upload.sh" *) Bash("${CLAUDE_SKILL_DIR}/scripts/delete.sh" *)
metadata:
  author: HurayraIIT
  version: "2.0"
---

# Cloudinary Uploader

Uploads local files to Cloudinary and returns short public **Share Links**, such as
`https://res.cloudinary.com/<cloud>/d/k3f9x2ab.png`. A Share Link uses a random name, never the original
filename, and never changes what it points to. Anyone with the link can open the file.

`${CLAUDE_SKILL_DIR}` is this skill's directory. If it appears below as literal text rather than a path,
use the directory this SKILL.md was loaded from.

## Uploading

```bash
"${CLAUDE_SKILL_DIR}/scripts/upload.sh" <file_path1> [file_path2 ...]
```

For each file that uploads, the script prints one tab-separated line to stdout:

```
<kind>	<file path as given>	<Share Link>
```

`kind` is `image` (including PDFs), `video` (including audio) or `raw` (anything else, such as logs, text or
archives). Errors and notes go to stderr, naming the file. A failed file doesn't stop the others, and the
script exits non-zero if any file failed. Match each Share Link to its file by the path column, not by
line order.

Before uploading, make sure the file is meant to be public: a screenshot can show secrets, tokens or
private data.

### Formatting the Share Links

Unless the user asked for something else, format by `kind`:
- `image`: an image embed, `![short description](LINK)`. For a PDF, use a link instead: `[name.pdf](LINK)`.
- `video` and `raw`: a link, `[short description](LINK)`.

### Limits and notes

- Files over 100 MB are refused before uploading. Cloudinary enforces the account's own limits (10 MB for
  images and raw files, 100 MB for videos on the Free plan) and its error names the real maximum; pass it on.
- HEIC/HEIF images get a `.jpg` Share Link so every browser can show them.
- If stderr has a note about PDF and archive links answering 401, pass it on to the user: their account
  blocks that delivery until they change a setting.

## Deleting

A Delete is permanent and can't be undone. **Only Delete when the user asks you to**, never on your own
judgement, even to undo a mistaken Upload: tell the user about the mistake and offer to Delete instead.

```bash
"${CLAUDE_SKILL_DIR}/scripts/delete.sh" [--yes] <share_link1> [share_link2 ...]
```

- Without `--yes` it's a dry run: it prints `would delete<TAB><kind> <public_id><TAB><link>` for each link
  and exits 2. Run it first if you're unsure a link is the right one.
- With `--yes` it Deletes, printing `deleted<TAB><link>`, or `already gone<TAB><link>` when the file no
  longer exists. The Share Link stops working within minutes.
- It only accepts Share Links in this account's own cloud, and refuses anything else.

## Credentials

Both scripts read `CLOUDINARY_URL` from the environment, then `~/.zshrc`, then `~/.bashrc` (a targeted
search, never sourced; the last assignment wins, like in the shell). Nothing else is checked. The format is
`cloudinary://<API_KEY>:<API_SECRET>@<CLOUD_NAME>`.

If it's missing, tell the user to add `export CLOUDINARY_URL=...` to `~/.zshrc` or `~/.bashrc`. Never ask
them to paste the value into the chat, and never print it.

## Examples

```bash
"${CLAUDE_SKILL_DIR}/scripts/upload.sh" /path/to/screenshot.png
"${CLAUDE_SKILL_DIR}/scripts/upload.sh" /path/to/1.png /path/to/demo.mp4 /path/to/app.log
"${CLAUDE_SKILL_DIR}/scripts/delete.sh" --yes https://res.cloudinary.com/demo/d/k3f9x2ab.png
```
