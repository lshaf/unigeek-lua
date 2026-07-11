# Morse Simulator

Tap out morse with the buttons; press OK to look the pattern up.

## Controls

| Button | Action |
|--------|--------|
| UP | add a dot (.) |
| DOWN | add a dash (-) |
| OK | look up the current buffer |
| BACK | exit |

A valid pattern shows the letter big in the centre and appends to the scrolling history. An unknown pattern shows "?" plus the failed code on the line below; the next UP / DOWN clears the error and starts a fresh entry. The buffer caps at MAX_MORSE_LEN symbols — extra presses past the cap just beep without changing the buffer.
