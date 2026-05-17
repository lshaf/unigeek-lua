# Scripts in this repo

Every `.lua` file here is browseable from the device's LUA menu under the same folder structure. To add a new script, drop it under a category folder (`utility/`, `game/`, etc.) — the Lua Runner walks sub-directories automatically.

When you add, rename, or remove a script, also update **[map.txt](map.txt)** at the repo root — that's the flat path list the firmware reads to enumerate everything available.

For how to *write* a script, see the [README](README.md). For the conventions enforced across the repo, see [CLAUDE.md](CLAUDE.md).

## Utility

| Path | Description |
|---|---|
| [utility/morse/generator.lua](utility/morse/generator.lua) | Enter text via on-screen keyboard, transmit it as morse code with a flashing lamp and matching audio tones. OK replays, BACK exits. |
| [utility/morse/simulator.lua](utility/morse/simulator.lua) | Tap out morse with the buttons — UP = dot, DOWN = dash, OK looks up the current buffer. Valid codes append to a scrolling history; unknown codes show `?` plus the failed pattern. BACK exits. |
| [utility/morse/training.lua](utility/morse/training.lua) | Browse the morse alphabet one letter at a time with synced audio + visual. UP/DOWN previous/next, OK replay, BACK exit. |

## Game

| Path | Description | Save file |
|---|---|---|
| [game/higher-lower.lua](game/higher-lower.lua) | Card guessing game. A value 1–13 is shown; UP = next will be higher, DOWN = next will be lower. Ties count as correct. Wrong guess ends the run; best streak is saved. | `/unigeek/games/higher-lower.txt` (best streak) |
| [game/invader.lua](game/invader.lua) | Space-invader clone. Move with UP/DOWN (or LEFT/RIGHT), fire with OK, BACK exits. | `/unigeek/games/invader.txt` (high score) |
| [game/stacker.lua](game/stacker.lua) | A coloured block slides at the top of the screen; OK drops it onto the stack. Any overhang gets trimmed and the next block inherits the trimmed width. Miss ends the game, stacking to the ceiling wins it. | `/unigeek/games/stacker.txt` (high score) |
