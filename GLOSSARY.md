# Cloudinary Uploader

An agent skill that turns local files into public Cloudinary links an agent can drop into GitHub issues, docs and chat. It shares its vocabulary with CloudDrop, the menu bar app that uploads to the same kind of account.

## Language

**Upload**:
Sending one local file to Cloudinary, ending in either a Share Link or a failure for that file alone.
_Avoid_: Sync, push, publish

**Kind**:
What Cloudinary treats an uploaded file as: an image (including PDFs), a video (including audio), or a raw file (anything else, such as a log, text file or archive). It decides how the Share Link is shaped and how the agent presents it.
_Avoid_: Type, resource type, MIME type

**Share Link**:
The short public URL of an uploaded file. It uses a random name that never reveals the original filename and never changes what it points to.
_Avoid_: URL, public link, secure URL, delivery URL

**Delete**:
Permanently removing an uploaded file from Cloudinary, identified by its Share Link and only in the account's own cloud. It happens only when the user asks for it. Its Share Link stops working within minutes, and it cannot be undone.
_Avoid_: Remove, destroy, unpublish

**Cloudinary URL**:
The single `cloudinary://key:secret@cloud` credential that identifies the account.
_Avoid_: API key, credentials, config
