# Metronome

A steady 4/4 click with an accented downbeat. The tempo is timed off uni.millis() (not delay-accumulation) so it stays accurate even while the screen redraws. A filled dot pulses on every beat; the four beat boxes light up in turn with the downbeat in a brighter colour.

## Controls

| Button | Action |
|--------|--------|
| UP | tempo +5 BPM   (40..240) |
| DOWN | tempo -5 BPM |
| OK | start / stop |
| BACK | exit |

In-memory only — there is nothing to save.
