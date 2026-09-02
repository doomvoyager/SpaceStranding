# Preview renders

Every image rendered from a capture scene and actually looked at lands here,
in a folder named for the day: `previews/YYYY-MM-DD/`.

Files are named `<capture-set>-<shot>.png`, so a day's folder can be browsed
flat as thumbnails rather than opened one subfolder at a time.

**Everything but this file is gitignored.** These are the visual record of a
session, not source: one day ran to 40 MB, and the notes in `docs/` cite the
shots rather than carrying them. Nothing here is regenerable *exactly* - the
capture scenes still exist, but the tuning sweeps that produced a number were
run against values that have since changed - which is the reason to keep them
locally at all.

Capture scenes write to Godot's `user://` first, because that is where a
running game can write without touching the project. The copy into here is a
step at the end of a capture run, listed in `CLAUDE.md`.
