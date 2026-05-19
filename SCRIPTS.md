# Scripts in this repo

Every `.lua` file here is browseable from the device's LUA menu under the same folder structure. To add a new script, drop it under a category folder (`utility/`, `game/`, etc.) — the Lua Runner walks sub-directories automatically.

When you add, rename, or remove a script, also update **[map.txt](map.txt)** at the repo root — that's the flat path list the firmware reads to enumerate everything available.

For how to *write* a script, see the [README](README.md). For the conventions enforced across the repo, see [CLAUDE.md](CLAUDE.md).

## Utility

| Path | Description |
|---|---|
| [utility/base-converter.lua](utility/base-converter.lua) | Enter a decimal value 0..65535, see it expressed in hex, octal, and binary (4-bit grouped) simultaneously. OK runs another conversion, BACK exits. |
| [utility/caesar-cipher.lua](utility/caesar-cipher.lua) | Caesar-cipher encode/decode. Enter text + shift amount (negative shifts decode); both the input and the result are shown. Non-letters pass through unchanged. |
| [utility/calculator.lua](utility/calculator.lua) | Two-operand arithmetic via modal prompts (`+`, `-`, `*`, `/`). Last 5 calculations kept in a scrolling history; divide-by-zero shows ERR. |
| [utility/clock.lua](utility/clock.lua) | Big `HH:MM:SS` clock with weekday + date underneath. Uses `uni.time` for the device RTC; warns if not yet synced via NTP. BACK exits. |
| [utility/coin-flip.lua](utility/coin-flip.lua) | Flip a virtual coin. OK flips with a short alternating-face animation; running tally (heads/tails) and a strip of the last flips live below the coin. BACK exits. |
| [utility/dice-roller.lua](utility/dice-roller.lua) | Roll a virtual die — d4, d6, d8, d10, d12, d20, d100. UP/DOWN cycles the die type, OK rolls with a short animation, recent rolls collect in a history strip. BACK exits (or aborts a roll in progress). |
| [utility/magic-8ball.lua](utility/magic-8ball.lua) | Ask a yes/no question, press OK, the ball shakes and reveals one of the 20 classic Magic 8-Ball answers tinted green/yellow/red by tone. BACK exits. |
| [utility/morse/generator.lua](utility/morse/generator.lua) | Enter text via on-screen keyboard, transmit it as morse code with a flashing lamp and matching audio tones. OK replays, BACK exits. |
| [utility/morse/simulator.lua](utility/morse/simulator.lua) | Tap out morse with the buttons — UP = dot, DOWN = dash, OK looks up the current buffer. Valid codes append to a scrolling history; unknown codes show `?` plus the failed pattern. BACK exits. |
| [utility/morse/training.lua](utility/morse/training.lua) | Browse the morse alphabet one letter at a time with synced audio + visual. UP/DOWN previous/next, OK replay, BACK exit. |
| [utility/stopwatch.lua](utility/stopwatch.lua) | `MM:SS.cc` stopwatch with up to 5 stored laps. OK starts/stops, UP records a lap while running, DOWN resets when stopped, BACK exits. In-memory only — exiting clears state. |

## Network

| Path | Description | Save file |
|---|---|---|
| [network/crypto-price.lua](network/crypto-price.lua) | Fetches BTC/USD and ETH/USD from the CoinGecko public API and shows them big in the centre, auto-refreshing every 60 s. If WiFi isn't already up, prompts for SSID + password; if a saved password exists at `/unigeek/wifi/passwords/*_<SSID>.pass` (same store the eapol bruteforce writes to), it's used automatically. OK refreshes / kicks off the connect prompt, BACK exits. | — (read-only on the firmware's `/unigeek/wifi/passwords/` store) |
| [network/hacker-news.lua](network/hacker-news.lua) | Top 10 stories from Hacker News, scrollable. Pulls `/topstories.json` then ten individual item fetches, renders titles in a list with a footer showing score, comment count, and author for the highlighted story. UP/DOWN scroll the cursor (wrap-around), OK refreshes, BACK exits. Auto-refreshes every 10 min. Same WiFi prompt + password-store convention as crypto-price. | — |
| [network/iss-tracker.lua](network/iss-tracker.lua) | Live position of the International Space Station, refreshed every 5 s from wheretheiss.at. Plots the station on a small bordered world rectangle (equator + prime meridian as faint grid) and shows lat/lon, altitude in km, velocity in km/h, and whether the station is in daylight or eclipse. OK forces an immediate refresh; BACK exits. Same WiFi prompt + password-store convention as crypto-price. | — |
| [network/weather.lua](network/weather.lua) | Current weather and today's high/low from open-meteo (no API key). First run prompts for latitude and longitude and saves them; pressing DOWN at any time re-enters the location. Shows big temperature, a condition label (clear / overcast / rain / thunderstorm …), high/low, wind and humidity. Auto-refreshes every 10 min, OK forces a refresh. Same WiFi prompt + password-store convention as crypto-price. | `/unigeek/network/weather.txt` (saved lat,lon) |

## Game

| Path | Description | Save file |
|---|---|---|
| [game/fishing-legend.lua](game/fishing-legend.lua) | Rarity-tiered fishing with shop, durable rods, stackable charms, day/night animated scene, and per-rarity sell prices. Cast (auto), wait for a bite, then either mash OK in MAN mode or let AUTO reel for you. Pity bonus boosts luck as rod durability runs low. Title menu has START / SHOP / INVENTORY / EXIT; UP/DOWN scrolls everywhere, OK confirms, BACK steps out one menu. Heap-heavy — needs ~`GAME_W × H × 2` bytes for the scene sprite; the script exits cleanly with a heap notice if allocation fails. | `/unigeek/games/fishing-legend.txt` (money, fish, rods, charms as JSON) |
| [game/higher-lower.lua](game/higher-lower.lua) | Card guessing game. A value 1–13 is shown; UP = next will be higher, DOWN = next will be lower. Ties count as correct. Wrong guess ends the run; best streak is saved. | `/unigeek/games/higher-lower.txt` (best streak) |
| [game/invader.lua](game/invader.lua) | Space-invader clone. Move with UP/DOWN (or LEFT/RIGHT), fire with OK, BACK exits. | `/unigeek/games/invader.txt` (high score) |
| [game/mastermind.lua](game/mastermind.lua) | 4-digit code breaker with coloured pegs. UP/DOWN cycles a digit (1–6), OK confirms and advances; OK on the fourth position submits the guess. After 10 attempts the secret is revealed. | `/unigeek/games/mastermind.txt` (lowest attempts to win) |
| [game/pong.lua](game/pong.lua) | Classic Pong against a tracking AI. UP/DOWN moves your paddle, OK serves, first to 5 wins. Ball direction varies with where it strikes the paddle. | `/unigeek/games/pong.txt` (lifetime wins/losses) |
| [game/reaction.lua](game/reaction.lua) | Reaction-time tester. A coloured panel cycles READY → WAIT → GO!; press OK as fast as you can after the green flash. Pressing during WAIT is a TOO-SOON fault. | `/unigeek/games/reaction.txt` (best ms) |
| [game/simon.lua](game/simon.lua) | Repeat the growing beep sequence. UP = red, OK = blue, DOWN = green; sequence grows by one each successful round. | `/unigeek/games/simon.txt` (rounds survived) |
| [game/snake.lua](game/snake.lua) | Classic snake with relative-turn controls. UP turns left of the snake's heading, DOWN turns right, OK pauses. Eat food, don't hit the wall or yourself. | `/unigeek/games/snake.txt` (food eaten) |
| [game/stacker.lua](game/stacker.lua) | A coloured block slides at the top of the screen; OK drops it onto the stack. Any overhang gets trimmed and the next block inherits the trimmed width. Endless: reaching the ceiling advances the level (faster slider, tighter cap); a miss ends the run. | `/unigeek/games/stacker.txt` (high score) |
| [game/tamagotchi.lua](game/tamagotchi.lua) | Virtual pet (cat/dog/bird). Hunger climbs, happiness and cleanliness drop over real-device time; feed, pet and clean to keep stats up. Face animates between three moods plus a happy wiggle. OK/UP/DOWN opens the action menu (Pet / Feed / Clean / Heart / Settings / New Pet / Exit), BACK saves and exits. | `/unigeek/games/tamagotchi.txt` (pet state as JSON) |
| [game/tic-tac-toe.lua](game/tic-tac-toe.lua) | Tic-Tac-Toe versus an unbeatable alpha-beta minimax AI. UP/DOWN cycles empty cells (skips occupied), OK places X. Player is X and always moves first. | `/unigeek/games/tic-tac-toe.txt` (wins/losses/draws as JSON) |
