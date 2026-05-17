# Scripts in this repo

Every `.lua` file here is browseable from the device's LUA menu under the same folder structure. To add a new script, drop it under a category folder (`utility/`, `game/`, etc.) — the Lua Runner walks sub-directories automatically.

When you add, rename, or remove a script, also update **[map.txt](map.txt)** at the repo root — that's the flat path list the firmware reads to enumerate everything available.

For how to *write* a script, see the [README](README.md). For the conventions enforced across the repo, see [CLAUDE.md](CLAUDE.md).

## Utility

| Path | Description |
|---|---|
| [utility/morse/generator.lua](utility/morse/generator.lua) | Enter text via on-screen keyboard, transmit it as morse code with a flashing lamp and matching audio tones. OK replays, BACK exits. |
| [utility/morse/simulator.lua](utility/morse/simulator.lua) | Tap out morse yourself — short touch / UP = dot, long hold / DOWN = dash. After a brief idle the buffer decodes to a letter; history accumulates in a scrolling line. OK commits immediately, BACK exits. |
| [utility/morse/training.lua](utility/morse/training.lua) | Browse the morse alphabet one letter at a time with synced audio + visual. UP/DOWN previous/next, OK replay, BACK exit. |

## Game

| Path | Description | Save file |
|---|---|---|
| [game/invader.lua](game/invader.lua) | Space-invader clone. Move with UP/DOWN (or LEFT/RIGHT), fire with OK, BACK exits. | `/unigeek/games/invader.txt` (high score) |
