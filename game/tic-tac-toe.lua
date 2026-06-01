-- tic-tac-toe.lua — Endless Tic-Tac-Toe vs AI
-- Sliding-piece variant: each side keeps at most 3 marks on the board. Placing
-- a 4th (the 7th turn for X, 8th for O) makes that side's OLDEST mark vanish, so
-- the board never fills and there are no draws — play runs until someone wins.
-- The mark about to disappear next is shown dimmed.
-- The AI runs a depth-limited alpha-beta minimax. Player is X (moves first), AI is O.
--
-- Controls depend on the board (nav.hasTouch()):
--   Touch boards  : tap a cell to place X there; tap anywhere to play again from
--                   the popup; tap the left edge (the BACK zone) to exit.
--   Button boards : UP/DOWN move to the previous/next empty cell, OK places X
--                   (or starts a new game from the popup), BACK exits.
--
-- Wins/losses persist as JSON in /unigeek/games/tic-tac-toe.txt.

local lcd  = require("uni.lcd")
local nav  = require("uni.nav")
local sd   = require("uni.sd")
local json = require("uni.json")

local W, H = lcd.w(), lcd.h()

-- Fixed per board: true on touch screens, false on button/stick/keyboard boards.
-- We branch the whole control scheme on this once, up front, rather than trying
-- to infer touch from a live finger-down poll.
local HAS_TOUCH = nav.hasTouch()

-- ── Colours ───────────────────────────────────────────────
local C_BG       = lcd.color(  8,  10,  30)
local C_HUD_BG   = lcd.color( 22,  22,  38)
local C_HUD_LINE = lcd.color( 60,  60,  90)
local C_TEXT     = lcd.color(220, 220, 240)
local C_DIM      = lcd.color(140, 140, 180)
local C_HI       = lcd.color(255, 200,  60)
local C_GOOD     = lcd.color(120, 220, 130)
local C_BAD      = lcd.color(255, 110, 110)
local C_GRID     = lcd.color( 80,  80, 110)
local C_X        = lcd.color(120, 220, 255)
local C_O        = lcd.color(255, 170, 100)
local C_X_DIM    = lcd.color( 55, 100, 115)   -- mark about to vanish
local C_O_DIM    = lcd.color(115,  78,  46)
local C_CURSOR   = lcd.color(255, 220,  80)
local C_WIN_LINE = lcd.color(255, 240, 120)

-- ── Layout ────────────────────────────────────────────────
local HUD_H   = 12
local HINT_Y  = H - 12
local AVAIL_H = HINT_Y - HUD_H - 4

local BOARD_SIZE = math.min(W - 20, AVAIL_H)
local CELL       = math.floor((BOARD_SIZE - 4) / 3)
local BOARD_W    = CELL * 3 + 4
local BOARD_X    = math.floor((W - BOARD_W) / 2)
local BOARD_Y    = HUD_H + 2 + math.floor((AVAIL_H - BOARD_W) / 2)

local SAVE_PATH = "/unigeek/games/tic-tac-toe.txt"

-- ── State (declared once) ─────────────────────────────────
local board         -- array[1..9]: 0 / "X" / "O"
local xq, oq        -- placement queues (oldest first), capped at 3 marks each
local cursor        -- 1..9 (always points at an empty cell during play)
local turn          -- "player" | "ai"
local game_state    -- "playing" | "over"
local outcome       -- "win" | "loss" (when over)
local winning_line  -- {a, b, c} or nil
local stats
local popup_drawn

local MAX_MARKS = 3   -- per side; a 4th placement removes the oldest
local MAX_DEPTH = 6   -- AI search horizon (the tree is infinite without one)

math.randomseed(uni.millis())

local LINES = {
  { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 },
  { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 },
  { 1, 5, 9 }, { 3, 5, 7 },
}

-- ── Helpers ───────────────────────────────────────────────
local function loadStats()
  if not sd.exists(SAVE_PATH) then return { wins = 0, losses = 0, draws = 0 } end
  local raw  = sd.read(SAVE_PATH) or ""
  local data = json.decode(raw)
  if not data then return { wins = 0, losses = 0, draws = 0 } end
  data.wins   = data.wins   or 0
  data.losses = data.losses or 0
  data.draws  = data.draws  or 0
  return data
end

local function saveStats()
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
  sd.write(SAVE_PATH, json.encode(stats))
end

local function cellRect(i)
  local row = math.floor((i - 1) / 3)
  local col = (i - 1) % 3
  local x   = BOARD_X + col * (CELL + 2)
  local y   = BOARD_Y + row * (CELL + 2)
  return x, y, CELL, CELL
end

local function checkWinner(brd)
  for _, line in ipairs(LINES) do
    local a, b, c = line[1], line[2], line[3]
    if brd[a] ~= 0 and brd[a] == brd[b] and brd[b] == brd[c] then
      return brd[a], line
    end
  end
  return nil, nil
end

-- Place mark at cell, pushing onto its queue. If the queue overflows MAX_MARKS,
-- the oldest mark is cleared from the board. Returns the removed cell (or nil) so
-- the move can be undone during search.
local function doMove(brd, q, cell, mark)
  brd[cell] = mark
  q[#q + 1] = cell
  if #q > MAX_MARKS then
    local removed = table.remove(q, 1)
    brd[removed] = 0
    return removed
  end
  return nil
end

local function undoMove(brd, q, cell, removed, mark)
  if removed then
    table.insert(q, 1, removed)
    brd[removed] = mark
  end
  table.remove(q)          -- pop the cell we just placed (now at the tail)
  brd[cell] = 0
end

-- Depth-limited alpha-beta minimax. AI is "O" (maximizer), player "X" (minimizer).
-- The win that just happened is detected on entry; the depth cap stops the search
-- since the sliding-piece game has no natural terminal/draw state.
local function minimax(brd, current, depth, alpha, beta)
  local w = checkWinner(brd)
  if w == "O" then return 100 - depth end
  if w == "X" then return depth - 100 end
  if depth >= MAX_DEPTH then return 0 end

  if current == "O" then
    local best = -1000
    for i = 1, 9 do
      if brd[i] == 0 then
        local removed = doMove(brd, oq, i, "O")
        local s = minimax(brd, "X", depth + 1, alpha, beta)
        undoMove(brd, oq, i, removed, "O")
        if s > best then best = s end
        if best > alpha then alpha = best end
        if beta <= alpha then break end
      end
    end
    return best
  else
    local best = 1000
    for i = 1, 9 do
      if brd[i] == 0 then
        local removed = doMove(brd, xq, i, "X")
        local s = minimax(brd, "O", depth + 1, alpha, beta)
        undoMove(brd, xq, i, removed, "X")
        if s < best then best = s end
        if best < beta then beta = best end
        if beta <= alpha then break end
      end
    end
    return best
  end
end

local function aiMove()
  -- Tiny opening book — saves a slow first-move minimax.
  local moves = 0
  for i = 1, 9 do if board[i] ~= 0 then moves = moves + 1 end end
  if moves == 1 then
    if board[5] == "X" then return 1 end                              -- center -> corner
    if board[1] == "X" or board[3] == "X"
       or board[7] == "X" or board[9] == "X" then return 5 end        -- corner -> center
    return 5                                                          -- edge   -> center
  end

  local best_score, best_move = -1000, nil
  for i = 1, 9 do
    if board[i] == 0 then
      local removed = doMove(board, oq, i, "O")
      local s = minimax(board, "X", 1, -1000, 1000)
      undoMove(board, oq, i, removed, "O")
      if s > best_score then
        best_score = s
        best_move  = i
      end
    end
  end
  return best_move
end

local function findEmpty(start, direction)
  for offset = 1, 9 do
    local i = ((start - 1 + offset * direction) % 9) + 9
    i = (i % 9) + 1
    if board[i] == 0 then return i end
  end
  return nil
end

local function findFirstEmpty()
  for i = 1, 9 do if board[i] == 0 then return i end end
  return nil
end

-- Map a touch coordinate to a board cell (1..9), or nil if it missed the grid.
local function cellAt(px, py)
  for i = 1, 9 do
    local x, y, w, _ = cellRect(i)
    if px >= x and px < x + w and py >= y and py < y + w then return i end
  end
  return nil
end

-- ── Rendering ─────────────────────────────────────────────
local function drawX(i, col)
  col = col or C_X
  local x, y, w, _ = cellRect(i)
  local m = math.max(4, math.floor(w * 0.18))
  for d = 0, 1 do
    lcd.line(x + m,         y + m + d,     x + w - m,     y + w - m + d,     col)
    lcd.line(x + m + d,     y + m,         x + w - m + d, y + w - m,         col)
    lcd.line(x + w - m,     y + m + d,     x + m,         y + w - m + d,     col)
    lcd.line(x + w - m + d, y + m,         x + m + d,     y + w - m,         col)
  end
end

local function drawO(i, col)
  col = col or C_O
  local x, y, w, _ = cellRect(i)
  local cx = x + math.floor(w / 2)
  local cy = y + math.floor(w / 2)
  local r  = math.max(6, math.floor(w * 0.32))
  for k = 0, 2 do
    lcd.circle(cx, cy, r - k, col)
  end
end

local function drawCell(i)
  local x, y, w, _ = cellRect(i)
  lcd.rect(x, y, w, w, C_BG)
  if     board[i] == "X" then drawX(i)
  elseif board[i] == "O" then drawO(i) end
end

-- Redraw a cell with its mark dimmed — used for the piece that vanishes next.
local function drawCellDim(i)
  local x, y, w, _ = cellRect(i)
  lcd.rect(x, y, w, w, C_BG)
  if     board[i] == "X" then drawX(i, C_X_DIM)
  elseif board[i] == "O" then drawO(i, C_O_DIM) end
end

-- When a side holds the max number of marks, dim the oldest (front of queue).
local function markDoomed(q)
  if #q >= MAX_MARKS then drawCellDim(q[1]) end
end

local function drawCursor()
  if HAS_TOUCH then return end   -- touch boards place by tapping; no cursor
  if game_state ~= "playing" or turn ~= "player" then return end
  local x, y, w, _ = cellRect(cursor)
  lcd.rect(x,         y,         w, 1, C_CURSOR)
  lcd.rect(x,         y + w - 1, w, 1, C_CURSOR)
  lcd.rect(x,         y,         1, w, C_CURSOR)
  lcd.rect(x + w - 1, y,         1, w, C_CURSOR)
end

local function drawGrid()
  for c = 1, 2 do
    local x = BOARD_X + c * CELL + (c - 1) * 2
    lcd.rect(x, BOARD_Y, 2, BOARD_W, C_GRID)
  end
  for r = 1, 2 do
    local y = BOARD_Y + r * CELL + (r - 1) * 2
    lcd.rect(BOARD_X, y, BOARD_W, 2, C_GRID)
  end
end

local function drawWinLine()
  if not winning_line then return end
  local xa, ya, w, _ = cellRect(winning_line[1])
  local xc, yc, _, _ = cellRect(winning_line[3])
  local ax = xa + math.floor(w / 2)
  local ay = ya + math.floor(w / 2)
  local bx = xc + math.floor(w / 2)
  local by = yc + math.floor(w / 2)
  for d = -1, 1 do
    lcd.line(ax + d, ay,     bx + d, by,     C_WIN_LINE)
    lcd.line(ax,     ay + d, bx,     by + d, C_WIN_LINE)
  end
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_HUD_LINE)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Tic-Tac-Toe")
  local s = string.format("W %d  L %d  D %d", stats.wins, stats.losses, stats.draws)
  lcd.textColor(C_HI, C_HUD_BG)
  local sw = lcd.textWidth(s)
  lcd.print(W - sw - 2, 2, s)
end

local function drawHint(text)
  lcd.rect(0, HINT_Y, W, 10, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local sw = lcd.textWidth(text)
  lcd.print(math.floor((W - sw) / 2), HINT_Y, text)
end

local function drawScene()
  lcd.fillScreen(C_BG)
  drawHUD()
  drawGrid()
  for i = 1, 9 do drawCell(i) end
  drawCursor()
end

local function drawPopup()
  local boxW = math.min(W - 16, 200)
  local boxH = 80
  local bx = math.floor((W - boxW) / 2)
  local by = math.floor((H - boxH) / 2)
  lcd.rect(bx, by, boxW, boxH, C_HUD_BG)
  lcd.rect(bx, by,             boxW, 1, C_DIM)
  lcd.rect(bx, by + boxH - 1,  boxW, 1, C_DIM)
  lcd.rect(bx, by,             1, boxH, C_DIM)
  lcd.rect(bx + boxW - 1, by,  1, boxH, C_DIM)

  lcd.textSize(2)
  local title, color
  if outcome == "win" then title, color = "YOU WIN!", C_GOOD
  else                     title, color = "AI WINS",  C_BAD end
  lcd.textColor(color, C_HUD_BG)
  local tw = lcd.textWidth(title)
  lcd.print(bx + math.floor((boxW - tw) / 2), by + 8, title)

  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  local s = string.format("W %d   L %d   D %d", stats.wins, stats.losses, stats.draws)
  local sw = lcd.textWidth(s)
  lcd.print(bx + math.floor((boxW - sw) / 2), by + 36, s)

  lcd.textColor(C_DIM, C_HUD_BG)
  local hint = HAS_TOUCH and "Tap: again   left edge: exit" or "OK: again   BACK: exit"
  local hw = lcd.textWidth(hint)
  lcd.print(bx + math.floor((boxW - hw) / 2), by + boxH - 14, hint)
end

-- ── Game flow ─────────────────────────────────────────────
local function startGame()
  board        = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  xq           = {}
  oq           = {}
  cursor       = 5
  turn         = "player"
  game_state   = "playing"
  outcome      = nil
  winning_line = nil
  popup_drawn  = false
end

local function afterMove(move_was_player)
  local w, line = checkWinner(board)
  if w == "X" then
    outcome      = "win"
    winning_line = line
    stats.wins   = stats.wins + 1
    saveStats()
    game_state   = "over"
    drawWinLine()
    return
  end
  if w == "O" then
    outcome      = "loss"
    winning_line = line
    stats.losses = stats.losses + 1
    saveStats()
    game_state   = "over"
    drawWinLine()
    return
  end
  if move_was_player then
    turn = "ai"
  else
    turn = "player"
    cursor = findFirstEmpty() or 1
    drawCursor()
  end
end

local function playerMove()
  if board[cursor] ~= 0 then
    uni.beep(200, 50)
    return
  end
  local placed  = cursor
  local removed = doMove(board, xq, cursor, "X")
  drawCell(placed)
  if removed then drawCell(removed) end
  markDoomed(xq)
  uni.beep(900, 30)
  afterMove(true)
end

local function makeAIMove()
  drawHint("AI thinking...")
  uni.delay(250)
  local move = aiMove()
  if not move then return end
  local removed = doMove(board, oq, move, "O")
  drawCell(move)
  if removed then drawCell(removed) end
  markDoomed(oq)
  uni.beep(550, 30)
  afterMove(false)
end

-- On touch boards every nav.btn() event is a tap, so we hit-test the cell it
-- landed on and only treat it as BACK when the tap missed every cell and fell in
-- the touch-nav BACK zone (left quarter) — the same trick the firmware main menu
-- uses. On button boards we never hit-test; the nav buttons drive everything.
local CONTROLS_HINT = HAS_TOUCH
  and "Tap a cell    tap left edge to exit"
  or  "UP/DOWN cell    OK place    BACK exit"

-- Place X at `cursor`, then (if the game continues) let the AI reply. Shared by
-- the OK button and a touch tap so both routes behave identically.
local function commitMove()
  playerMove()
  if game_state == "playing" and turn == "ai" then
    makeAIMove()
    drawHint(CONTROLS_HINT)
    drawHUD()
  else
    drawHUD()
  end
end

-- ── Init ──────────────────────────────────────────────────
stats = loadStats()
startGame()
drawScene()
drawHint(CONTROLS_HINT)

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()

  if game_state == "playing" then
    if turn == "player" and btn ~= "none" then
      if HAS_TOUCH then
        -- Touch board: the event is a tap. Hit-test the cell it landed on; a tap
        -- that missed every cell only exits when it fell in the BACK zone. Nav
        -- directions are ignored here — on a touch board you place by tapping.
        local cell = cellAt(nav.touchX(), nav.touchY())
        if cell then
          if board[cell] == 0 then
            cursor = cell         -- playerMove() places at `cursor`
            commitMove()
          else
            uni.beep(200, 50)     -- tapped an occupied cell
          end
        elseif btn == "back" then
          break                   -- a real back: tap missed every cell
        end
      else
        -- Button board: cursor navigation.
        if btn == "up" or btn == "down" then
          local dir = (btn == "up") and -1 or 1
          local next_pos = findEmpty(cursor, dir)
          if next_pos and next_pos ~= cursor then
            local prev = cursor
            cursor = next_pos
            drawCell(prev)
            drawCursor()
            uni.beep(900, 12)
          end
        elseif btn == "ok" then
          commitMove()
        elseif btn == "back" then
          break
        end
      end
    end
  else
    if not popup_drawn then
      drawHUD()
      drawPopup()
      popup_drawn = true
    end
    if btn ~= "none" then
      if btn == "back" then break end   -- BACK / left-zone tap exits
      startGame()                       -- OK / any other tap starts a new game
      drawScene()
      drawHint(CONTROLS_HINT)
    end
  end

  uni.delay(33)
end
