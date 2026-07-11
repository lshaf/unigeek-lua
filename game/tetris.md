# Tetris

Standard 10x20 well, 7-bag randomiser, line clears, levels that speed up gravity every 10 lines. A short lock delay lets you still slide a piece after it lands.

## Controls

| Button | Action |
|--------|--------|
| UP / LEFT | move left |
| DOWN / RIGHT | move right |
| OK | rotate clockwise |
| BACK | exit (also dismisses the Game Over popup) |

The default UniGeek board has only up/down/ok/back, and exit owns BACK — that leaves three gameplay buttons. Horizontal movement takes up/down (the same trade-off invader.lua makes) and OK rotates, so there is no manual hard-drop; gravity lands the piece. Boards with left/right work too.

All drawing is per-cell overdraw against a painted-state cache — no lcd.clear()/fillScreen() inside the loop, no closures allocated per frame. High score (lines cleared) persists to /unigeek/games/tetris.txt.
