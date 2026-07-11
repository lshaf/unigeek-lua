# Tic-Tac-Toe

Sliding-piece variant: each side keeps at most 3 marks on the board. Placing a 4th (the 7th turn for X, 8th for O) makes that side's OLDEST mark vanish, so the board never fills and there are no draws — play runs until someone wins. The mark about to disappear next is shown dimmed. The AI runs a depth-limited alpha-beta minimax. Player is X (moves first), AI is O.

Controls depend on the board (nav.hasTouch()):   Touch boards  : tap a cell to place X there; tap anywhere to play again from                   the popup; tap the left edge (the BACK zone) to exit.   Button boards : UP/DOWN move to the previous/next empty cell, OK places X                   (or starts a new game from the popup), BACK exits.

Wins/losses persist as JSON in /unigeek/games/tic-tac-toe.txt.
