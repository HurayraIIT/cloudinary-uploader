# Cloudinary uploader skill for AI agents

An [Agent Skill](https://agentskills.io) that lets your AI agent (Claude Code, Codex, Cursor and
others) upload local screenshots, images, videos and files to Cloudinary and hand you back a short public
link, like `https://res.cloudinary.com/your-cloud/d/k3f9x2ab.png`: ready to drop into a GitHub issue, a
doc or a chat message.

It's a single bash script that signs and sends uploads with `curl`. No SDK, no dependencies to
install, and no build step.

## What you need

- **macOS or Linux** with `bash`, `curl` and `file` (all come preinstalled). `jq` or `python3` is used to
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

You should see a line like `image  /path/to/some-image.png  https://res.cloudinary.com/...`. Open the
link to check the upload.

If you installed without `-g`, the same folders are inside your project instead of your home
folder.

## Using it

Talk to your agent normally. You don't need to mention the skill or the word "Cloudinary":

- *Upload this screenshot and give me a link: ~/Desktop/bug.png*
- *File a GitHub issue for this bug and attach the two screenshots in ~/Downloads as evidence.*
- *Host the recording at ./demo.mp4 so I can share it in Slack.*

Images come back as Markdown image embeds (`![](...)`), everything else as links.

To remove something you uploaded by mistake, ask: *Delete https://res.cloudinary.com/.../d/k3f9x2ab.png*.
A Delete is permanent, and the link stops working within minutes. The agent only Deletes when you ask.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `CLOUDINARY_URL is not set` | Add the `export` line to `~/.zshrc` or `~/.bashrc` (step 3). Only those two files and the environment are checked; `~/.profile`, `~/.bash_profile` and `.env` files are not. |
| `CLOUDINARY_URL from … isn't a Cloudinary URL` | The saved value is wrong, for example `CLOUDINARY_URL=` pasted twice. The line should read `export CLOUDINARY_URL=cloudinary://...` (step 3). If it's set more than once, the last line wins, and `~/.zshrc` wins over `~/.bashrc`. |
| Still using an old value after changing it | A `CLOUDINARY_URL` environment variable takes priority over the files. Run `unset CLOUDINARY_URL` or restart your terminal and agent. |
| `Invalid Signature` or `Invalid api_key` | The key or secret was mistyped or regenerated. Copy the URL again (step 2). |
| `File size too large. Got … Maximum is …` | The file is over your Cloudinary plan's limit (on Free: 10 MB for images and other files, 100 MB for videos). Compress or trim it first. |
| `over Cloudinary's 100 MB limit for a single upload` | The skill doesn't upload files over 100 MB on any plan. |
| A PDF or ZIP link answers `401` | Free accounts block PDF and archive delivery. Turn on **Allow delivery of PDF and ZIP files** in [Settings → Security](https://console.cloudinary.com/app/settings/security). A link opened before the change can stay blocked for a while because of caching. |
| `the name d/… is already taken` | A one-in-a-trillion clash with an existing upload. Run the upload again. |
| A `.log` or `.txt` link downloads instead of showing | Cloudinary serves raw files as downloads. That's expected. |
| `Permission denied` running `upload.sh` | Run `chmod +x` on the script, or call it with `bash upload.sh ...`. |

## How it works

Each file is uploaded with a signed request to `api.cloudinary.com` under a random name such as
`d/k3f9x2ab`, and the skill builds the short link itself. Your original filename never appears in the
link; it's kept as the file's display name in the Cloudinary console. Uploads never overwrite each other,
so a link always shows the file it was made for. Files land in a console folder named `clouddrop`, shared
with the author's [CloudDrop](https://github.com/HurayraIIT/cloudinary-drop) menu bar app.

The script prints one line per uploaded file, `<kind><TAB><path><TAB><link>`, and exits non-zero if any
file fails.

**Privacy:** your Cloudinary URL stays on your computer. The skill talks only to
`api.cloudinary.com`, and only when asked to upload. Uploaded files are **public**: anyone with the
link can open them.

For agents and the curious: [SKILL.md](SKILL.md) is what the agent reads, [GLOSSARY.md](GLOSSARY.md)
defines the terms, and [docs/adr/](docs/adr/) records why things are the way they are.

## What changed in 2.0

- **Short, private links.** Links are about 50 characters, with a random name instead of the filename.
  Uploads made with 1.x keep their old links.
- **New output.** Each line is `<kind><TAB><path><TAB><link>` instead of a bare URL, so every link can
  be matched to its file even when one in a batch fails.
- **Larger videos.** The fixed 10 MB limit is gone; your Cloudinary plan's limits apply, up to 100 MB.
- **Deleting.** `scripts/delete.sh` permanently Deletes uploads, when you ask.
- **Fixes.** Two files with the same name uploaded in the same second no longer replace each other,
  slow uploads aren't cut off after 60 seconds, and `CLOUDINARY_URL` is read from shell files the way
  the shell reads it.

## Development

Run the offline tests with `tests/run.sh`. They never touch the network.

## License

[MIT](LICENSE)
