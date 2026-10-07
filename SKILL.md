---
name: cloudinary-uploader
description: >
  Upload local images, videos, and files to Cloudinary and return their public URL.
  Use when the user wants to share a local screenshot, image, video, or file via a
  public hosted link — including when preparing visual evidence for GitHub issues,
  documentation, or chat messages. Also use for batch-uploading multiple local assets.
  Triggers even when the user doesn't say "Cloudinary" explicitly but wants a hosted
  public URL for a local file.
license: MIT
compatibility: Requires bash and curl (jq or python3 optional) and a CLOUDINARY_URL. macOS and Linux.
allowed-tools: Bash("${CLAUDE_SKILL_DIR}/scripts/upload.sh" *)
metadata:
  author: HurayraIIT
  version: "1.0"
---

# Cloudinary Uploader

This skill enables AI agents to upload local images, videos, and files directly to Cloudinary so you can easily share public links in chats, documentation, or format them as visual evidence (e.g. for GitHub issues).

## When to use

Use this skill whenever you are asked to:
- Upload a local file (such as a screenshot, generated image, log file, or video recording) to Cloudinary.
- Get a public URL for a local file.
- Prepare visual evidence or assets to attach to a GitHub issue.
- Batch upload multiple files at once.

## Running the script

```bash
"${CLAUDE_SKILL_DIR}/scripts/upload.sh" <file_path1> [file_path2 ...]
```

`${CLAUDE_SKILL_DIR}` is this skill's directory. If it appears above as literal text rather than a
path, use the directory this SKILL.md was loaded from.

## Credentials

The script reads `CLOUDINARY_URL` from (in order):
1. The current environment
2. A targeted grep of `~/.zshrc`, then `~/.bashrc` (no sourcing; commented lines are ignored)

Nowhere else is checked. The expected format is `cloudinary://<API_KEY>:<API_SECRET>@<CLOUD_NAME>`.
If it's missing, tell the user to add `export CLOUDINARY_URL=...` to `~/.zshrc` or `~/.bashrc`.
Never ask them to paste the value into the chat.

## Instructions

1. Identify the file path(s) of the local asset(s) you need to upload.
2. Run `scripts/upload.sh` as shown above. You can pass one or multiple file paths separated by spaces.
3. The script extracts credentials from `CLOUDINARY_URL`, signs the request, and uploads each file. The `public_id` is prefixed with a `YYMMDD_HHMMSS_` timestamp to avoid collisions.
4. The script prints the **direct URL(s)** of uploaded assets to stdout (one per line). All errors are printed to stderr. The script exits non-zero if any upload fails.
5. **IMPORTANT (Formatting):** Format the URL(s) in Markdown depending on the file type:
   - For **images**, use an image embed: `![](URL)`
   - For **videos** or other files (PDF, txt, zip, etc.), use a text link: `[Link Description](URL)`
   - Or follow any specific formatting the user requested.

### File size limit

The script enforces a 10 MB pre-upload limit per file. Files larger than 10 MB are skipped with an error on stderr.

### Example usage

Single file:
```bash
"${CLAUDE_SKILL_DIR}/scripts/upload.sh" /path/to/screenshot.png
```

Batch uploading multiple files:
```bash
"${CLAUDE_SKILL_DIR}/scripts/upload.sh" /path/to/1.png /path/to/2.mp4
```
