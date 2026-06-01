-- tetris.lua — Tetris for the UniGeek Lua Runner
-- Standard 10x20 well, 7-bag randomiser, line clears, levels that speed up
-- gravity every 10 lines. A short lock delay lets you still slide a piece
-- after it lands.
--
--   UP    / LEFT  : move left
--   DOWN  / RIGHT : move right
--   OK            : rotate clockwise
--   BACK          : exit (also dismisses the Game Over popup)
--
-- The default UniGeek board has only up/down/ok/back, and exit owns BACK —
-- that leaves three gameplay buttons. Horizontal movement takes up/down (the
-- same trade-off invader.lua makes) and OK rotates, so there is no manual
-- hard-drop; gravity lands the piece. Boards with left/right work too.
--
-- All drawing is per-cell overdraw against a painted-state cache — no
-- lcd.clear()/fillScreen() inside the loop, no closures allocated per frame.
-- High score (lines cleared) persists to /unigeek/games/tetris.txt.

local lcd = require("uni.lcd")
local nav = require("uni.nav")
local sd  = require("uni.sd")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG      = lcd.color(  6,   8,  22)
local C_HUD_BG  = lcd.color( 22,  22,  38)
local C_HUD_LN  = lcd.color( 60,  60,  90)
local C_TEXT    = lcd.color(220, 220, 240)
local C_DIM     = lcd.color(140, 140, 180)
local C_HI      = lcd.color(255, 200,  60)
local C_GOOD    = lcd.color(120, 220, 130)
local C_BORDER  = lcd.color( 70,  74, 110)
local C_GRID    = lcd.color( 18,  20,  40)   -- gridline colour (shows in gaps)
local C_EMPTY   = lcd.color( 11,  13,  30)   -- empty cell fill

local C_I = lcd.color( 80, 210, 240)
local C_O = lcd.color(240, 210,  70)
local C_T = lcd.color(190, 110, 240)
local C_S = lcd.color(110, 220, 120)
local C_Z = lcd.color(240, 100, 100)
local C_J = lcd.color(100, 130, 240)
local C_L = lcd.color(245, 160,  70)

-- ── Pieces: 4 rotation states, cells as {col,row} in a 4x4 box (0..3) ──
local PIECES = {
  { color = C_I, rot = {
      {{0,1},{1,1},{2,1},{3,1}}, {{2,0},{2,1},{2,2},{2,3}},
      {{0,2},{1,2},{2,2},{3,2}}, {{1,0},{1,1},{1,2},{1,3}} } },
  { color = C_O, rot = {
      {{1,0},{2,0},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{2,1}},
      {{1,0},{2,0},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{2,1}} } },
  { color = C_T, rot = {
      {{1,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{2,1},{1,2}},
      {{0,1},{1,1},{2,1},{1,2}}, {{1,0},{0,1},{1,1},{1,2}} } },
  { color = C_S, rot = {
      {{1,0},{2,0},{0,1},{1,1}}, {{1,0},{1,1},{2,1},{2,2}},
      {{1,1},{2,1},{0,2},{1,2}}, {{0,0},{0,1},{1,1},{1,2}} } },
  { color = C_Z, rot = {
      {{0,0},{1,0},{1,1},{2,1}}, {{2,0},{1,1},{2,1},{1,2}},
      {{0,1},{1,1},{1,2},{2,2}}, {{1,0},{0,1},{1,1},{0,2}} } },
  { color = C_J, rot = {
      {{0,0},{0,1},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{1,2}},
      {{0,1},{1,1},{2,1},{2,2}}, {{1,0},{1,1},{0,2},{1,2}} } },
  { color = C_L, rot = {
      {{2,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{1,2},{2,2}},
      {{0,1},{1,1},{2,1},{0,2}}, {{0,0},{1,0},{1,1},{1,2}} } },
}

local COLS, ROWS = 10, 20
local LINE_SCORE = { 40, 100, 300, 1200 }   -- by lines cleared at once (x level)
local LOCK_MS    = 350
local SPAWN_PX, SPAWN_PY = 4, 1

local SAVE_PATH = "/unigeek/games/tetris.txt"

-- ── Layout ────────────────────────────────────────────────
-- Fit the layout to the actual screen by computing, from W and H, the cell
-- size each panel placement would allow, then using whichever fills the well
-- more. The well is 10x20 (tall), so on a narrow/tall screen a bottom strip
-- wins (keep full width); on a wide/square screen a right sidebar wins (height
-- is the scarce dimension). CELL is the resulting block size in pixels.
local HUD_H, M = 12, 3
local SB_W     = math.min(54, math.floor(W * 0.34))
local STRIP_H  = 34

local cell_side  = math.min(math.floor((W - 6 - SB_W) / COLS),
                            math.floor((H - HUD_H - 6) / ROWS))
local cell_strip = math.min(math.floor((W - 2 * M) / COLS),
                            math.floor((H - STRIP_H - HUD_H - 4) / ROWS))
local portrait   = cell_strip >= cell_side

local CELL, FIELD_W, FIELD_H, FIELD_X, FIELD_Y, PCELL
local NXL_X, NXL_Y, NX_X, NX_Y
local S1_LX, S1_LY, S1_VX, S1_VY
local S2_LX, S2_LY, S2_VX, S2_VY

if portrait then
  CELL    = math.max(4, cell_strip)
  FIELD_W = CELL * COLS
  FIELD_H = CELL * ROWS
  FIELD_X = math.floor((W - FIELD_W) / 2)
  local avail_h = H - STRIP_H - HUD_H - 4
  FIELD_Y = HUD_H + 2 + math.max(0, math.floor((avail_h - FIELD_H) / 2))

  local info_y = H - STRIP_H
  PCELL  = math.max(3, math.floor((STRIP_H - 4) / 4))
  NXL_X, NXL_Y = M, info_y + math.floor((STRIP_H - 8) / 2)
  NX_X,  NX_Y  = M + 28, info_y + math.floor((STRIP_H - PCELL * 4) / 2)
  local base = NX_X + PCELL * 4 + 14
  S1_LX, S1_LY, S1_VX, S1_VY = base, info_y + 4,  base + 34, info_y + 4
  S2_LX, S2_LY, S2_VX, S2_VY = base, info_y + 18, base + 34, info_y + 18
else
  CELL    = math.max(4, cell_side)
  FIELD_W = CELL * COLS
  FIELD_H = CELL * ROWS
  FIELD_X = M
  FIELD_Y = HUD_H + 2 + math.max(0, math.floor((H - HUD_H - 2 - FIELD_H) / 2))

  local SB_X = FIELD_X + FIELD_W + 5
  PCELL = math.max(3, math.min(CELL, math.floor((W - SB_X - 4) / 4)))
  NXL_X, NXL_Y = SB_X, FIELD_Y
  NX_X,  NX_Y  = SB_X, FIELD_Y + 12
  local statY = NX_Y + PCELL * 4 + 8
  S1_LX, S1_LY, S1_VX, S1_VY = SB_X, statY,      SB_X, statY + 9
  S2_LX, S2_LY, S2_VX, S2_VY = SB_X, statY + 24, SB_X, statY + 33
end

-- ── State (declared once) ─────────────────────────────────
local grid          -- grid[r][c] = 0 or colour
local painted       -- painted[r][c] = colour currently on screen
local bag           -- 7-bag of piece indices
local cur, nxt      -- current / next piece index (1..7)
local rot, px, py   -- current rotation (1..4) and box offset
local resting       -- piece can't fall; lock countdown running
local lock_at       -- millis() deadline to lock
local next_fall     -- millis() of the next gravity step
local score, lines, level
local gdrop         -- gravity interval (ms)
local state         -- "play" | "over"
local popup_drawn
local highScore

-- shown sentinels for the sidebar / HUD text
local shown_score, shown_lines, shown_level, shown_nxt

-- pre-allocated scratch for the 4 active-piece cells (no per-frame alloc)
local pcr = { 0, 0, 0, 0 }
local pcc = { 0, 0, 0, 0 }

math.randomseed(uni.millis())

-- ── Save / load ───────────────────────────────────────────
local function loadHigh()
  if not sd.exists(SAVE_PATH) then return 0 end
  return tonumber(sd.read(SAVE_PATH) or "") or 0
end

local function saveHigh(n)
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
  sd.write(SAVE_PATH, tostring(n))
end

-- ── Randomiser (7-bag) ────────────────────────────────────
local function refillBag()
  bag = { 1, 2, 3, 4, 5, 6, 7 }
  for i = 7, 2, -1 do
    local j = math.random(i)
    bag[i], bag[j] = bag[j], bag[i]
  end
end

local function drawFromBag()
  if not bag or #bag == 0 then refillBag() end
  return table.remove(bag)
end

-- ── Collision / piece maths ───────────────────────────────
local function collides(rotIdx, ox, oy)
  local cells = PIECES[cur].rot[rotIdx]
  for k = 1, 4 do
    local bc = ox + cells[k][1]
    local br = oy + cells[k][2]
    if bc < 1 or bc > COLS or br > ROWS then return true end
    if br >= 1 and grid[br][bc] ~= 0 then return true end
  end
  return false
end

local function refreshPieceCells()
  local cells = PIECES[cur].rot[rot]
  for k = 1, 4 do
    pcc[k] = px + cells[k][1]
    pcr[k] = py + cells[k][2]
  end
end

-- ── Rendering ─────────────────────────────────────────────
local function drawBlock(r, c, col)
  local x = FIELD_X + (c - 1) * CELL
  local y = FIELD_Y + (r - 1) * CELL
  lcd.rect(x, y, CELL - 1, CELL - 1, col)   -- 1px gap reveals the grid bg
end

-- Diff-render the well: paint only cells whose colour changed since last frame.
local function composeRender()
  local pcolor = PIECES[cur].color
  for r = 1, ROWS do
    local growrid = grid[r]
    local prow    = painted[r]
    for c = 1, COLS do
      local want = growrid[c]
      if state == "play" and
         ((r == pcr[1] and c == pcc[1]) or (r == pcr[2] and c == pcc[2]) or
          (r == pcr[3] and c == pcc[3]) or (r == pcr[4] and c == pcc[4])) then
        want = pcolor
      end
      if want == 0 then want = C_EMPTY end
      if prow[c] ~= want then
        drawBlock(r, c, want)
        prow[c] = want
      end
    end
  end
end

local function drawNext()
  -- clear the preview box, then draw the next piece in its 4x4 area
  lcd.rect(NX_X, NX_Y, PCELL * 4, PCELL * 4, C_EMPTY)
  local p = PIECES[nxt]
  for k = 1, 4 do
    local c = p.rot[1][k][1]
    local r = p.rot[1][k][2]
    lcd.rect(NX_X + c * PCELL, NX_Y + r * PCELL, PCELL - 1, PCELL - 1, p.color)
  end
  shown_nxt = nxt
end

-- The label/value anchors are positioned by the layout block, so this draws
-- the same way whether the panel is a right sidebar or a bottom strip.
local function drawSidebar()
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(NXL_X, NXL_Y, "NEXT")
  drawNext()
  lcd.textColor(C_DIM, C_BG)
  lcd.print(S1_LX, S1_LY, "LINES")
  lcd.textColor(C_TEXT, C_BG)
  lcd.print(S1_VX, S1_VY, string.format("%-4d", lines))
  lcd.textColor(C_DIM, C_BG)
  lcd.print(S2_LX, S2_LY, "LEVEL")
  lcd.textColor(C_HI, C_BG)
  lcd.print(S2_VX, S2_VY, string.format("%-4d", level))
  shown_lines, shown_level = lines, level
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_HUD_LN)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Tetris")
  lcd.textColor(C_HI, C_HUD_BG)
  local s = string.format("%d", score)
  lcd.print(W - lcd.textWidth(s) - 2, 2, s)
  shown_score = score
end

-- Static frame + a forced full repaint of the well.
local function drawStaticFrame()
  lcd.fillScreen(C_BG)
  drawHUD()
  -- field border + gridline backing (1px gaps in drawBlock reveal C_GRID)
  lcd.rect(FIELD_X - 2, FIELD_Y - 2, FIELD_W + 4, FIELD_H + 4, C_BORDER)
  lcd.rect(FIELD_X - 1, FIELD_Y - 1, FIELD_W + 2, FIELD_H + 2, C_GRID)
  for r = 1, ROWS do
    for c = 1, COLS do painted[r][c] = -1 end   -- sentinel: force redraw
  end
  drawSidebar()
end

local function drawPopup()
  local boxW = math.min(W - 16, 150)
  local boxH = 70
  local bx = math.floor((W - boxW) / 2)
  local by = math.floor((H - boxH) / 2)
  lcd.rect(bx, by, boxW, boxH, C_HUD_BG)
  lcd.rect(bx, by, boxW, 1, C_DIM)
  lcd.rect(bx, by + boxH - 1, boxW, 1, C_DIM)
  lcd.rect(bx, by, 1, boxH, C_DIM)
  lcd.rect(bx + boxW - 1, by, 1, boxH, C_DIM)

  lcd.textSize(2)
  lcd.textColor(C_HI, C_HUD_BG)
  local t = "GAME OVER"
  lcd.print(bx + math.floor((boxW - lcd.textWidth(t)) / 2), by + 8, t)

  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  local s = string.format("Lines %d   Best %d", lines, highScore)
  lcd.print(bx + math.floor((boxW - lcd.textWidth(s)) / 2), by + 32, s)
  lcd.textColor(C_DIM, C_HUD_BG)
  local h = "OK again   BACK exit"
  lcd.print(bx + math.floor((boxW - lcd.textWidth(h)) / 2), by + boxH - 14, h)
end

-- ── Game flow ─────────────────────────────────────────────
local function applyLevel()
  level = math.floor(lines / 10) + 1
  gdrop = math.max(80, 550 - (level - 1) * 45)
end

local function spawn()
  cur = nxt
  nxt = drawFromBag()
  rot, px, py = 1, SPAWN_PX, SPAWN_PY
  resting = false
  next_fall = uni.millis() + gdrop
  if shown_nxt ~= nxt then drawNext() end
  if collides(rot, px, py) then
    state = "over"
    if lines > highScore then highScore = lines; saveHigh(highScore) end
  end
  refreshPieceCells()
end

local function clearLines()
  local cleared = 0
  local r = ROWS
  while r >= 1 do
    local full = true
    for c = 1, COLS do
      if grid[r][c] == 0 then full = false; break end
    end
    if full then
      cleared = cleared + 1
      -- shift everything above down by one
      for rr = r, 2, -1 do
        for c = 1, COLS do grid[rr][c] = grid[rr - 1][c] end
      end
      for c = 1, COLS do grid[1][c] = 0 end
      -- re-test the same row (now holding what fell into it)
    else
      r = r - 1
    end
  end
  if cleared > 0 then
    lines = lines + cleared
    score = score + (LINE_SCORE[cleared] or 0) * level
    applyLevel()
    uni.beep(cleared >= 4 and 1500 or 880, 40)
  end
end

local function lockPiece()
  local cells = PIECES[cur].rot[rot]
  for k = 1, 4 do
    local bc = px + cells[k][1]
    local br = py + cells[k][2]
    if br >= 1 then grid[br][bc] = PIECES[cur].color end
  end
  uni.beep(440, 14)
  clearLines()
  spawn()
end

local function startGame()
  grid    = {}
  for r = 1, ROWS do
    grid[r] = {}
    for c = 1, COLS do grid[r][c] = 0 end
  end
  score, lines = 0, 0
  applyLevel()
  refillBag()
  nxt = drawFromBag()
  state = "play"
  popup_drawn = false
  shown_nxt = -1
  spawn()
end

-- Try a horizontal step; reset lock grace if it succeeds while resting.
local function tryMove(d)
  if collides(rot, px + d, py) then return end
  px = px + d
  refreshPieceCells()
  if resting then lock_at = uni.millis() + LOCK_MS end
end

-- Rotate clockwise with a simple wall-kick (try in place, then nudge ±1).
local function tryRotate()
  local nr = (rot % 4) + 1
  local kick
  if     not collides(nr, px, py)     then kick = 0
  elseif not collides(nr, px - 1, py) then kick = -1
  elseif not collides(nr, px + 1, py) then kick = 1 end
  if kick then
    rot, px = nr, px + kick
    refreshPieceCells()
    if resting then lock_at = uni.millis() + LOCK_MS end
  end
end

-- ── Init ──────────────────────────────────────────────────
painted = {}
for r = 1, ROWS do painted[r] = {} end
highScore = loadHigh()
startGame()
drawStaticFrame()
composeRender()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if state == "play" then
    if btn == "up" or btn == "left" then
      tryMove(-1)
    elseif btn == "down" or btn == "right" then
      tryMove(1)
    elseif btn == "ok" then
      tryRotate()
    end

    local now = uni.millis()
    if not resting then
      if now >= next_fall then
        if collides(rot, px, py + 1) then
          resting = true
          lock_at = now + LOCK_MS
        else
          py = py + 1
          refreshPieceCells()
          next_fall = now + gdrop
        end
      end
    else
      if not collides(rot, px, py + 1) then
        resting = false                 -- slid over a gap; keep falling
        py = py + 1
        refreshPieceCells()
        next_fall = now + gdrop
      elseif now >= lock_at then
        lockPiece()                     -- locks, clears lines, spawns next
      end
    end

    composeRender()

    if score ~= shown_score then drawHUD() end
    if lines ~= shown_lines or level ~= shown_level then drawSidebar() end
  else
    if not popup_drawn then
      drawPopup()
      popup_drawn = true
    end
    if btn == "ok" then
      startGame()
      drawStaticFrame()
      composeRender()
    end
  end

  uni.delay(24)
end
