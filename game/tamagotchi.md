# Tamagotchi

Bruce launcher. Pet decays over time: hunger climbs, happiness and cleanliness drop. Feed / pet / clean to keep stats up. State persists to /unigeek/games/tamagotchi.txt as JSON across power cycles (uses the RTC epoch, so decay only accumulates if the device clock has been synced).

## Controls

| Button | Action |
|--------|--------|
| OK / UP / DOWN | open action menu (Pet / Feed / Clean / Heart / Settings / |

                   New Pet / Exit). The default UniGeek board only has                    four nav inputs, so any non-back press opens the menu —                    that mirrors the original "any key brings up choices".

## Controls

| Button | Action |
|--------|--------|
| BACK | save and exit. |

All in-loop drawing uses overdraw + textColor(fg, bg). Helpers are pre-allocated above the while loop so no closures churn per frame.
