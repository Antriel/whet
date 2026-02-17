---
# whet-7iin
title: 'Bug: RemoteFile error path throws inside callback instead of rejecting promise'
status: completed
type: bug
priority: high
created_at: 2026-02-14T08:29:35Z
updated_at: 2026-02-17T07:49:52Z
parent: whet-4ve1
---


RemoteFile.get throws from async callback (`src/whet/stones/RemoteFile.hx:31`) and does not wire response/request error events. Network failures can escape Promise control flow and crash process instead of returning structured rejection.
