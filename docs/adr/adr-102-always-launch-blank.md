# ADR-102: The viewer always launches blank

**Status:** Accepted · **Date:** 2026-10-24 · **Amends:** adr-100 §3

## Context

adr-100 decided that opening a folder enters full screen but a restored session
does not, so the app would never seize the screen at launch. That decision
assumed a restored session existed at all: the first build wrote the folder path
to `UserDefaults` and reopened it on the next launch.

Living with the app changed the requirement. Reopening the last folder means
launching a viewer shows photographs you may not have wanted to see — someone
else's screen, a client's shoot, the folder you were sorting last night. It also
makes "the app stole the screen" reachable again through the back door, because
the restore path is the one the app takes on every launch.

## Decision

1. **No session restore.** The folder is not persisted and is not reopened. Every
   launch is the empty state: one action, four keys, nothing on screen.
2. **View preferences still persist.** Column count, hold time, and fill mode are
   properties of how you watch, not of what you watched; they survive a relaunch.
3. **An explicit folder is still allowed.** `--folder <path>` opens a show for
   that launch only. It is how scripts and the UI tests start without the panel,
   and it is not written down either.

## Consequences

Launching the app is now always safe and always the same, which is the property
that matters for something you keep in the Dock. The cost is a keystroke: a
folder you were watching yesterday needs ⌘O again today, and the app cannot be
used as a hands-off digital frame across a restart without a launch argument or a
login item that passes one.

Removing the restore also removed a whole class of state: there is no
`slideshow.folderPath` key to migrate, corrupt, or explain, and the model's
initializer no longer touches the file system.

## Alternatives considered

- **Restore the folder but never full screen** (the adr-100 position) — still
  shows whatever was last opened to whoever opens the app next; rejected.
- **Restore only on explicit relaunch, not login** — the distinction is not
  observable to the user and adds a launch-origin flag to maintain; rejected.
- **Remember a "watch this folder" favourite** — a real feature (a saved folder
  you choose deliberately), but it is a different feature with its own UI, not a
  silent default; deferred.
