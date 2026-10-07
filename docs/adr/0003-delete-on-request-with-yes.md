# Delete only on request, with `--yes`, pre-approved for agents

An agent that uploads the wrong file, or a screenshot showing a secret, leaves it public until someone opens the console. So the skill has `delete.sh <share-link>`, which takes the Kind and public_id from the link and sends Cloudinary's signed `destroy` with `invalidate=true`, so the Share Link stops working within minutes rather than being served from the CDN cache. It refuses links whose cloud isn't the Cloudinary URL's, and otherwise accepts any public_id shape, including older root uploads and CloudDrop's.

The skill is used by autonomous agents, so `delete.sh` is in `allowed-tools` like `upload.sh`, and the harness doesn't prompt. The guard is behavioural instead: SKILL.md lets the agent Delete only when the user asks, never on its own judgement, and without `--yes` the script only prints what it would Delete and exits 2, so a mistaken call does nothing.

## Considered Options

- **Leaving `delete.sh` out of `allowed-tools`** so the harness asks every time: rejected because it blocks unattended agents.
- **Letting the agent Delete its own mistaken Uploads unasked**: rejected, a Delete can't be undone.
- **Refusing without `--yes`**: a dry run costs nothing and shows whether the link parsed as expected.
