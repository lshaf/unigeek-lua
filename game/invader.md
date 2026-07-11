# Space Invaders

## Controls

| Button | Action |
|--------|--------|
| UP / LEFT | move ship left |
| DOWN / RIGHT | move ship right |
| OK | fire |
| BACK | exit (also dismisses the Game Over popup) |

Default UniGeek hardware only has up/down/ok/back, so the ship is moved with up/down. Boards that have left/right still work too.

Endless: clearing a wave advances to the next level. Each level speeds up the invader march, increases enemy fire rate, and gradually raises enemy bullet speed. Score and lives carry over; the run ends only when lives reach 0 or the invaders touch the player.

All movement uses overdraw — no lcd.clear()/fillScreen() inside the loop. Helpers are declared before the main while-loop so no closures churn in the hot path. High score persists to /unigeek/games/invader.txt.
