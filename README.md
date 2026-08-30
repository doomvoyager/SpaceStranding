# Space Stranding

A traversal-first, non-combat cargo-hauling game set on a tidally locked
exoplanet. You drive a rover between settlements strung along the twilight band,
haul cargo that behaves like cargo, extend a line-of-sight relay network, and
find out what the planet is.

Godot 4.7.1, third-person 3D, GDScript.

Design docs are an Obsidian vault in [`docs/`](docs/) - start at
[`docs/00-Index.md`](docs/00-Index.md).

## Layout

    game/       Godot project (res://)
    docs/       Design documentation - open this folder as an Obsidian vault
    engine/     Portable Godot install. Gitignored, per-machine.
    tools/      Standalone authoring tools (none yet)

## Running

Godot is not installed system-wide. It lives in `engine/`, per machine:

```bash
engine/Godot.app/Contents/MacOS/Godot --path game
```

On Windows the binary is `engine/Godot_v4.7.1-stable_win64_console.exe`.

Headless boot check, which surfaces script errors without opening the editor:

```bash
engine/Godot.app/Contents/MacOS/Godot --headless --path game --quit-after 120
```

## Controls

| Input | On foot | In rover |
|---|---|---|
| `W` `A` `S` `D` | Move | Throttle / steer |
| `Space` | Jump | Brake |
| `Shift` | Sprint | — |
| `E` | Enter rover | Exit rover |
| `Esc` | Release mouse | Release mouse |
| Mouse | Look | Look |

## Status

Traversal slice: procedural terrain, an astronaut controller tuned for 0.34 g,
and a drivable six-wheel rover with enter/exit. Cargo, flares, the relay
network and the mobile base are designed but not built - see the build-status
table in [`docs/00-Index.md`](docs/00-Index.md).
