# Space Stranding

A traversal-first, non-combat cargo-hauling game set at the lunar south pole,
50-80 years from now. You drive a rover between settlements strung along the
lit crater rims, haul cargo that behaves like cargo, and extend a line-of-sight
relay network.

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

Traversal slice on the Moon's 1.62 m/s^2: authored terrain, the astronaut on
foot, a governed six-wheel rover, cargo that takes damage, orders, and a
line-of-sight relay network you raise by hand. Flares and the mobile base are
designed but not built - see the build-status table in
[`docs/00-Index.md`](docs/00-Index.md).
