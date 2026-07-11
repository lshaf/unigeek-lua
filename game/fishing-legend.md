# Fishing Legend

JavaScript app for the Bruce launcher). Rarity-tiered fishing with a shop, durable rods, stackable charms, drop-rate luck mechanics + pity bonus, day/night animated scene, and per-rarity sell prices.

Controls (default UniGeek 4-button board):

## Controls

| Button | Action |
|--------|--------|
| UP / DOWN | cursor / scroll. While fishing: toggle MAN <-> AUTO mode. |
| OK | confirm / cast / mash-reel (MAN) / sell / equip / buy / toggle. |
| BACK | back / exit. |

The fishing scene composes into a half-screen off-screen sprite that is pushed once per frame. The right-half sidebar (Recent / Top Luck / Stats) renders directly with lcd.* and only repaints on need_full_redraw. Menu screens render directly via lcd.* with diff-rendered cursor rows.

All state persists to /unigeek/games/fishing-legend.txt as JSON (money, fish items, rod inventory, charm inventory). Fish / rod / charm databases are hardcoded above — edit the tables in this file to mod.
