# Short Share Links, shaped exactly like CloudDrop's

Share Links used to be Cloudinary's `secure_url`: a version segment plus a `YYMMDD_HHMMSS_<filename>` public_id, over 100 characters, revealing the filename. Two files with the same name uploaded in the same second also got the same public_id, and the default overwrite made the first link silently serve the second file. Now every Upload gets CloudDrop's shape: a random 8-character `a-z0-9` name in the `d/` URL folder, the `clouddrop` console folder (`asset_folder`), and the original filename as `display_name`. The skill builds the Share Link itself, without a version: `https://res.cloudinary.com/<cloud>/d/k3f9x2ab.png` for images (Cloudinary's root path form), `/video/upload/d/…` for videos and audio, `/raw/upload/d/….log` for raw files, whose public_id must carry the extension. HEIC/HEIF links end in `.jpg`. Dropping the version is only safe because a name is never reused, so Uploads send `overwrite=false` and treat Cloudinary's `"existing": true` reply (an HTTP 200) as a failed Upload, without retrying.

The Kind is decided locally from the file's MIME type and sent to the explicit `image`, `video` or `raw` endpoint, not `auto`: a raw public_id needs its extension and an image's must not have one, so the Kind has to be known before the public_id is built.

## Considered Options

- **A separate URL folder (`s/`) or console folder for the skill**: rejected to keep one shape, so CloudDrop's Delete and Link History treat the skill's Uploads as their own.
- **A configurable console folder**: no one has asked for it, and it's one more setting to read from shell files. Strangers get a `clouddrop` folder, which the README explains.
- **`/auto/upload`**: can't produce correct raw and image public_ids, see above.

## Consequences

CloudDrop's Link History searches the `clouddrop` folder for the 10 newest assets and skips raw files, so each raw Upload from the skill shortens that list by one until newer Uploads push it out. This was accepted rather than changing CloudDrop's search.
