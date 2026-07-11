# Scoreboard

Reads every game's save file under /unigeek/games/ and lists each one's best result on a single screen. Games store scores in different shapes (a bare number, a best time in ms, or a wins/losses JSON record), so each entry below declares how to format its file. Games that haven't been played yet show a dim dash.

## Controls

| Button | Action |
|--------|--------|
| UP / DOWN | scroll the list (when it doesn't all fit) |
| OK | re-read the files (refresh after playing something) |
| BACK | exit |

Read-only — this script never writes to the save files.
