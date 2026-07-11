# Mastermind

The device picks a secret 4-digit code where each digit is 1..6. Enter your guesses one digit at a time; after each full guess the feedback pegs tell you how close you are:   ● filled red peg = right digit in the right position   ○ outlined peg   = right digit in the wrong position 10 attempts to crack it. Best (lowest-attempt) win is saved.

## Controls

| Button | Action |
|--------|--------|
| UP | cycle digit at cursor up   (1 -> 2 -> .. -> 6 -> 1) |
| DOWN | cycle digit at cursor down (1 -> 6 -> 5 -> .. -> 1) |
| OK | confirm digit and advance (at position 4 = submit guess) |
| BACK | exit (also dismisses Game Over / You Win) |
