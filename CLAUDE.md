# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of Lua 5.1 scripts that run on the **UniGeek ESP32 firmware's Lua Runner**. There is no build step, no test suite, no package manager — each `.lua` file is dropped onto the device's SD card and executed in place.

Folder layout in this repo mirrors the on-device path. `utility/morse/generator.lua` here maps to `/unigeek/lua/utility/morse/generator.lua` on the SD card. Sub-folders are browsable from the LUA menu.

## Authoritative API reference

**Always read [../unigeek/knowledge/lua-runner.md](../unigeek/knowledge/lua-runner.md) before writing or modifying a script.** That file documents the exact runtime: execution model, every available module and method, anti-flicker patterns, the "context block" to paste into AI tools, and the canonical example (`bounce.lua`). It is the source of truth — the rules below are a summary of what most commonly trips people up.

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

Via `require`: `uni.lcd` (display + sprites), `uni.sd` (file I/O), `uni.nav` (buttons + touch), `uni.input` (modal text/number/hex/ip prompts), `uni.dialog` (confirm/select), `uni.notify` (toast), `uni.json`, `uni.path`, `uni.time` (RTC), `uni.config` (device settings).

## Existing scripts as reference

- [utility/morse/generator.lua](utility/morse/generator.lua) — modal input prompt followed by audio + visual playback. Demonstrates the pre-allocated helper pattern, overdraw for the lamp, `lcd.textColor(fg,bg)` for changing text, and BACK-polling between every dot/dash so playback cancels cleanly.
- [utility/morse/simulator.lua](utility/morse/simulator.lua) — input-driven navigation between states (left/right/ok/back), with playback that bubbles any nav press back up to the main loop instead of swallowing it.

When adding a new tool, follow the same shape: one file per script, all `require` calls and helpers declared once at the top, then a single `while true do` loop that polls `nav.btn()`, mutates pre-declared locals, redraws only what changed, and ends with `uni.delay(16)` (~60 fps) or larger.

## Firmware download integration

The UniGeek firmware downloads scripts from this repo over WiFi — see `_fetchLuaLevel` in [../unigeek/firmware/src/screens/wifi/network/DownloadScreen.cpp](../unigeek/firmware/src/screens/wifi/network/DownloadScreen.cpp) (around line 701). If you change anything about how the firmware browses this repo (manifest format, directory listing scheme, path layout), the parser there is the contract you have to satisfy.
