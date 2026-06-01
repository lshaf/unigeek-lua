# Contributing

Thanks for adding to the unigeek-lua collection. This guide covers the conventions and the must-do checklist for every new script.

## Before you start

- Read the [README](README.md) for the full Lua Runner API and the rules that prevent the most common crashes (no `lcd.clear()` inside the loop, no inline closures, Lua 5.1 quirks). For the complete, authoritative reference (mirrored from the firmware) see **[docs/lua-runner.md](docs/lua-runner.md)**.
- Open an existing script in the same category — it's the most concrete spec of what "good" looks like:
  - [utility/morse/generator.lua](utility/morse/generator.lua) — modal text input + audio/visual playback with mid-playback cancellation.
  - [utility/morse/simulator.lua](utility/morse/simulator.lua) — touch hold-detection with button fallback and idle-timeout decoding.
  - [utility/morse/training.lua](utility/morse/training.lua) — state navigation that bubbles input back to the main loop instead of swallowing it.
  - [game/invader.lua](game/invader.lua) — pure overdraw game loop, fixed-pool entities, AABB collisions, persistent high score.

## Folder layout

The repo's folder structure mirrors the on-device path: `utility/morse/generator.lua` here is `/unigeek/lua/utility/morse/generator.lua` on the SD card. Use an existing category where it fits; create a new top-level folder only when nothing fits.

| Folder | Goes here |
|---|---|
| `utility/` | Standalone tools — single-purpose scripts that do one thing well |
| `game/` | Games and interactive demos that own state and often a high-score file |
| `network/` | Scripts that need `uni.wifi` / `uni.http` — anything that talks to the network |

File names are lowercase, no spaces. Single words are preferred (`generator.lua`, `invader.lua`); use a hyphen for multi-word (`color-picker.lua`).

## When you add, rename, or remove a script

Update **both** indexes in the same change. If you skip one, either the device or the catalogue will be wrong:

1. **[map.txt](map.txt)** at the repo root — flat list, one repo-relative path per line, no headers, no comments, sorted alphabetically. The firmware reads this once to enumerate everything available.
2. **[SCRIPTS.md](SCRIPTS.md)** at the repo root — human-readable catalogue. Add a row to the right category section with controls and any save-file path.

## Default-hardware controls

The default UniGeek board exposes only four nav inputs: `up`, `down`, `ok`, `back`. Do **not** design a script that only works with `left` / `right` — those events only fire on board variants with a full d-pad or joystick. If left/right is the natural mapping, accept both so the script still works on every board:

```lua
if btn == "left"  or btn == "up"   then move_left()  end
if btn == "right" or btn == "down" then move_right() end
```

Reserve `ok` for confirm/fire/select and `back` for exit.

## Save data

Persistent state — high scores, settings, history — goes in `/unigeek/games/<name>.txt`. **Not** in `/unigeek/lua/` (that path is reserved for scripts). Make sure the directory exists before writing:

```lua
if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
sd.write("/unigeek/games/myscript.txt", state)
```

## Testing

There is no automated test suite — scripts must be tested on a real device. At minimum:

1. The script starts without errors.
2. Every button does what its on-screen hint says.
3. `BACK` exits cleanly from every screen, including modal popups.
4. No flicker — if there is, you're calling `lcd.clear()` / `lcd.fillScreen()` inside the loop. Move it to a one-shot state-entry path.
5. Long-running scripts (games, animations) don't leak memory — check that `uni.heap()` doesn't trend down across hundreds of frames. If it does, you almost certainly have an inline closure in the hot loop.

## Commit style

- One short subject line. No bullet points, no body.
- Start with a random emoji — any emoji. It does *not* need to relate to the change. Randomness is the point.
- No `Co-Authored-By` trailer.

Examples from this repo's history:

- `🦒 add flat script path map`
- `🐙 add interactive morse simulator`
- `🍉 document default buttons and scripts reference`

## Submitting

Open a PR against `main`. In the description mention:

- What the script does (one-line summary).
- Which hardware variant you tested on.
- Anything reviewers should pay particular attention to — heap usage if it runs forever, frame timing if it's animation-heavy, sprite size if you allocate one.

If you're modifying an existing script, call out any behaviour changes that users will notice.
