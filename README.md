# Cloudinary uploader skill for AI agents

An [Agent Skill](https://agentskills.io) that lets your AI agent (Claude Code, Codex, Cursor and
others) upload local screenshots, images, videos and files to Cloudinary and hand you back a public
link: ready to drop into a GitHub issue, a doc or a chat message.

It's a single bash script that signs and sends uploads with `curl`. No SDK, no dependencies to
install, and no build step.

## What you need

- **macOS or Linux** with `bash` and `curl` (both come preinstalled). `jq` or `python3` is used to
  read Cloudinary's response when available, but neither is required.
- **A Cloudinary account**; the free plan works
- **An AI agent that supports skills**, such as Claude Code, Codex or Cursor

Setup takes about three minutes: install the skill, then save your Cloudinary URL.

## 1. Install the skill

Run this in a terminal:

```bash
npx skills@latest add hurayraiit/cloudinary-uploader -g
```

When asked, pick the agents you use. `-g` installs the skill for your user account, so it works in
every project. Leave `-g` off to install it into the current project only.

To update later, run `npx skills update`. To remove it, run `npx skills remove cloudinary-uploader -g`.

## 2. Get your Cloudinary URL

1. Sign in at **[console.cloudinary.com](https://console.cloudinary.com)**.
2. Open **Settings** (the gear icon) → **API Keys**.
3. Copy the **API environment variable**. It looks like
   `CLOUDINARY_URL=cloudinary://123456789012345:abcdEFGHijkl@your-cloud-name`.

The API secret in this URL can upload and delete anything in your account, so treat it like a
password. Don't paste it into chats or commit it to git.

## 3. Save the URL

The skill reads `CLOUDINARY_URL` from your environment, or from `~/.zshrc` or `~/.bashrc`. It reads
those files with a targeted search and never runs them. Keeping the value in your shell config
rather than the skill folder means updating the skill never deletes it.

Add this line to `~/.zshrc` (the default shell on macOS) or `~/.bashrc`, using your own URL:

```bash
export CLOUDINARY_URL=cloudinary://123456789012345:abcdEFGHijkl@your-cloud-name
```

For example, on macOS:

```bash
open -e ~/.zshrc
```

Paste the line, then save and close. Because the skill reads the file directly, this works even for
agents you don't start from a terminal.

## 4. Check that it works

Ask your agent:

> Upload a test screenshot to Cloudinary and give me the link.

Or run it yourself. Where the skill lives depends on the agents you picked in step 1: it's in
`.claude/skills/cloudinary-uploader` when Claude Code was among them, otherwise in
`.agents/skills/cloudinary-uploader`, both inside your home folder.

```bash
~/.claude/skills/cloudinary-uploader/scripts/upload.sh /path/to/some-image.png
# or, if that folder doesn't exist:
~/.agents/skills/cloudinary-uploader/scripts/upload.sh /path/to/some-image.png
```

You should see a `https://res.cloudinary.com/...` link. Open it to check the upload.

If you installed without `-g`, the same folders are inside your project instead of your home
folder.

## Using it

Talk to your agent normally. You don't need to mention the skill or the word "Cloudinary":

- *Upload this screenshot and give me a link: ~/Desktop/bug.png*
- *File a GitHub issue for this bug and attach the two screenshots in ~/Downloads as evidence.*
- *Host the recording at ./demo.mp4 so I can share it in Slack.*

Images come back as Markdown image embeds (`![](...)`), everything else as links.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `CLOUDINARY_URL is not set` | Add the `export` line to `~/.zshrc` or `~/.bashrc` (step 3). Only those two files and the environment are checked; `~/.profile`, `~/.bash_profile` and `.env` files are not. |
| `CLOUDINARY_URL must start with 'cloudinary://'` | The saved value is wrong, for example `CLOUDINARY_URL=` pasted twice. The line should read `export CLOUDINARY_URL=cloudinary://...` (step 3). |
| Still using an old value after changing it | A `CLOUDINARY_URL` environment variable takes priority over the files. Run `unset CLOUDINARY_URL` or restart your terminal and agent. |
| `Invalid Signature` or `Invalid api_key` | The key or secret was mistyped or regenerated. Copy the URL again (step 2). |
| `exceeding the 10MB limit` | The skill refuses files over 10 MB. Compress or trim the file first. |
| `Permission denied` running `upload.sh` | Run `chmod +x` on the script, or call it with `bash upload.sh ...`. |

## How it works

Each file is uploaded with a signed request to `api.cloudinary.com` under the name
`YYMMDD_HHMMSS_<original-name>`, so uploads never overwrite each other. The script prints one URL
per line and exits non-zero if any file fails.

**Privacy:** your Cloudinary URL stays on your computer. The skill talks only to
`api.cloudinary.com`, and only when asked to upload. Uploaded files are **public**: anyone with the
link can open them.

For agents and the curious: [SKILL.md](SKILL.md) is what the agent reads.

## License

[MIT](LICENSE)
