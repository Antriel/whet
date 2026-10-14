---
# whet-391c
title: Graceful file-system handling, whet-wide
status: draft
type: feature
priority: low
created_at: 2026-10-14T10:32:47Z
updated_at: 2026-10-14T10:32:47Z
---

Whet does raw `fs` calls everywhere (FileCache, Stone.exportTo/setAbsolutePath outputs, `TrackedFile`
for authored inputs). On Windows, a rename/unlink/open can fail transiently with EPERM/EBUSY/EACCES
while another program (Dropbox, antivirus, an editor, the indexer) briefly holds the file, and
too many parallel opens can hit EMFILE.

Look into the idiomatic way tools like this handle it before picking one:
- `graceful-fs` (npm's approach: patches `fs`, queues on EMFILE, retries Windows rename for up to
  ~60s with backoff),
- `write-file-atomic` (temp + rename, used by npm),
- a small local retry helper around rename/unlink only.

First concrete user: `TrackedFile.write` (temp + rename of authored JSON files that live in
Dropbox, whet-vz93), which currently has no retry.
