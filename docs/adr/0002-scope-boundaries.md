# Deliberately out of scope

The skill does one thing: it turns local files into Share Links, and Deletes them when the user asks. These were considered and left out:
- transformations, except that HEIC/HEIF Share Links deliver JPEG
- listing or a history of Uploads (CloudDrop's Link History covers that)
- renaming
- uploading from the clipboard, stdin or a remote URL
- chunked uploads, so nothing over 100 MB, the largest single request Cloudinary accepts
- retries
- any other cloud service

The only size check on the machine is that 100 MB ceiling. Per-plan limits (10 MB images, 100 MB videos and 10 MB raw files on Free, more on paid plans) are left to Cloudinary, whose error names the real maximum. A hard-coded Free-plan check would wrongly refuse files on paid plans; the cost is that an oversized file on Free is sent before it's refused.

Before adding any of these, revisit this decision.
