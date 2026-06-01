re# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of Lua 5.1 scripts that run on the **UniGeek ESP32 firmware's Lua Runner**. There is no build step, no test suite, no package manager — each `.lua` file is dropped onto the device's SD card and executed in place.

Folder layout in this repo mirrors the on-device path. `utility/morse/generator.lua` here maps to `/unigeek/lua/utility/morse/generator.lua` on the SD card. Sub-folders are browsable from the LUA menu.

## Authoritative API reference

**Always read [docs/lua-runner.md](docs/lua-runner.md) before writing or modifying a script.** That file documents the exact runtime: execution model, every available module and method, anti-flicker patterns, the "context block" to paste into AI tools, and the canonical example (`bounce.lua`). It is the source of truth — the rules below are a summary of what most commonly trips people up. (It is a mirror of `knowledge/lua-runner.md` in the UniGeek firmware repo, kept in-repo so it's available from a standalone clone; the firmware copy is canonical if the two ever diverge.)

## Execution model essentials

- The runner compiles the script once and `lua_pcall()`s it exactly once on a dedicated FreeRTOS task. The script owns the call stack — write a `while true do … end` loop and `break` to exit. The runner exits automatically when the script returns.
- `nav.btn()` returns `"back"` when the user presses Back; the script must detect this and `break` itself.
- Locals declared **before** the loop persist for the whole session — use them instead of globals. Locals **inside** the loop are re-created each iteration.
- `uni.delay(ms)` is required inside every loop; without it the watchdog will trip. Nav state stays fresh across delays.

## Critical rules (these are the ones that cause crashes / flicker)

1. **Never call `lcd.clear()` or `lcd.fillScreen()` inside the while loop.** Draw the static background once *before* the loop. Inside the loop, either overdraw the previous bounding box (1–2 px larger than the sprite), use `lcd.textColor(fg, bg)` + `string.format` padding for changing text, or compose into an `lcd.sprite()` and `push()` once per frame.
2. **No inline closures in the hot loop.** Writing `function(...) ... end` as a callback argument inside `while true` allocates a new closure every frame; at 60 fps this fragments internal SRAM and crashes after ~10 minutes. Pre-allocate the function as a local before the loop and pass the name.
3. **Lua 5.1, not 5.3.** No `//` integer division — use `math.floor(a/b)`. `math.floor()` floats before passing as `lcd` coordinates.
4. **No `io` / `os` / `debug` libraries.** All file access goes through `require("uni.sd")`. `require("mymodule")` does **not** load `.lua` files — only the `uni.*` modules are available via require.
5. Game/state saves go in `/unigeek/games/<name>.txt`, never `/unigeek/lua/`.
6. `lcd.sprite(w, h)` allocates `w*h*2` bytes from internal heap and returns `nil` on OOM — always check.

## Available modules

Globals (no require): `uni.debug`, `uni.delay`, `uni.millis`, `uni.heap`, `uni.beep`.

Via `require`: `uni.lcd` (display + sprites), `uni.sd` (file I/O), `uni.nav` (buttons + touch), `uni.input` (modal text/number/hex/ip prompts), `uni.dialog` (confirm/select), `uni.notify` (toast), `uni.json`, `uni.path`, `uni.time` (RTC), `uni.config` (device settings), `uni.wifi` (station-mode connect/status), `uni.http` (blocking GET/POST, TLS via setInsecure).

**Network notes:** if a script calls `wifi.connect()` and succeeds, the runner auto-disconnects on exit. If WiFi was already up before the script ran, it's left alone. `http.get`/`post` require `wifi.status() == "connected"`; responses are capped at 256 KB (over-cap returns `nil, -3`).

## Hardware: default button layout

**The default UniGeek hardware exposes only four nav inputs: `"up"`, `"down"`, `"ok"`, and `"back"`.** The Lua Runner API also defines `"left"` and `"right"`, but those events only fire on board variants with a full d-pad / joystick. Anything distributed in this repo has to work on the default board.

When designing a script:
- Use **up / down** for any horizontal or "previous / next" action — even when "left / right" would be the more obvious mapping (e.g. movement in a side-scroller, browsing a list).
- If left / right *would* feel natural and the script targets boards that have them, accept **both** so the script still works on the default board:
  ```lua
  if btn == "left" or btn == "up"   then move_left()  end
  if btn == "right" or btn == "down" then move_right() end
  ```
- Reserve `ok` for confirm / fire / select, and `back` for exit. Don't repurpose them.

## Existing scripts as reference

There are **two indexes** that must stay in sync with the script files:

- **[SCRIPTS.md](SCRIPTS.md)** — user-facing catalogue: grouped by category, with controls and save-file paths.
- **[map.txt](map.txt)** — flat machine-readable list. One repo-relative `.lua` path per line, no headers, no comments. The firmware reads this once to enumerate every script in the repo without having to walk sub-directory manifests.

**When you add, rename, or remove a script, update both files in the same change.** The README does not duplicate either list; it just links to SCRIPTS.md.

Concrete patterns to study before writing a new one:

- [utility/morse/generator.lua](utility/morse/generator.lua) — modal input prompt followed by audio + visual playback. Pre-allocated helpers, overdraw for the lamp, `lcd.textColor(fg,bg)` for changing text, BACK-polling between every dot/dash so playback cancels cleanly.
- [utility/morse/simulator.lua](utility/morse/simulator.lua) — explicit UP/DOWN/OK input with diff-rendered regions. Demonstrates explicit-commit UX (no idle timeout), per-region state tracking with sentinel "shown" values, and a "no match" error path that's dismissed by the next input.
- [utility/morse/training.lua](utility/morse/training.lua) — input-driven navigation between states (up/down/ok/back), with playback that bubbles any nav press back up to the main loop instead of swallowing it.
- [game/invader.lua](game/invader.lua) — pure overdraw game loop with many moving entities, fixed-pool bullets, AABB collisions, persistent high score via `uni.sd`.

When adding a new tool, follow the same shape: one file per script, all `require` calls and helpers declared once at the top, then a single `while true do` loop that polls `nav.btn()`, mutates pre-declared locals, redraws only what changed, and ends with `uni.delay(16)` (~60 fps) or larger.

## Firmware download integration

The UniGeek firmware downloads scripts from this repo over WiFi — see `_fetchLuaLevel` in [../unigeek/firmware/src/screens/wifi/network/DownloadScreen.cpp](../unigeek/firmware/src/screens/wifi/network/DownloadScreen.cpp) (around line 701). The firmware reads [map.txt](map.txt) once to get a flat list of every script path in the repo, then fetches whichever ones the user selects. If you change the layout, naming, or contents of `map.txt`, the parser there is the contract you have to satisfy.

## Contribution flow for human users

External and self-contribution rules live in [CONTRIBUTING.md](CONTRIBUTING.md): folder conventions, the two-index sync rule, default-hardware controls, save paths, the on-device testing checklist, and commit style. When a human user asks "how do I add a script?" point them there. The rules in this CLAUDE.md and CONTRIBUTING.md mirror each other — keep them aligned if you change one.

## Git commits

Follow the user's global commit style stored in `~/.claude/memory/feedback_git_commits.md`. The rules:

- **No co-author trailer.** Never append `Co-Authored-By: Claude …` or any other co-author line.
- **Lead with a random emoji.** Pick any emoji — it does **not** need to relate to what the commit changes. The randomness is the point; don't waste cycles trying to find a "fitting" one.
- **Short overview only.** One subject line. No bullet points, no body, no detailed explanation.
- **Commit granularity.** Files inside folders (`utility/foo.lua`, `game/bar.lua`, `network/baz.lua`, …) get one commit per file. Files at the repo root (`README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `SCRIPTS.md`, `map.txt`, etc.) are bundled into a single commit together.

Example: `📡 initial morse generator + simulator + docs`
