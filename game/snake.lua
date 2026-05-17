-- snake.lua — Snake (relative-turn)
-- The snake auto-advances along the grid; you steer it by turning
-- relative to its current heading. Eat food to grow, don't hit a
-- wall or yourself.
--
--   UP   : turn left  (counterclockwise from current heading)
--   DOWN : turn right (clockwise from current heading)
--   OK   : pause / resume
--   BACK : exit (also dismisses Game Over)
--
-- High score (food eaten) persists to /unigeek/games/snake.txt.

local lcd = require("uni.lcd")
local nav = require("uni.nav")
local sd  = require("uni.sd")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG       = lcd.color(  6,   8,  22)
local C_HUD_BG   = lcd.color( 22,  22,  38)
local C_HUD_LINE = lcd.color( 60,  60,  90)
local C_TEXT     = lcd.color(220, 220, 240)
local C_DIM      = lcd.color(140, 140, 180)
local C_HI       = lcd.color(255, 200,  60)
local C_BAD      = lcd.color(255, 110, 110)
local C_GOOD     = lcd.color( 80, 220, 120)
local C_SNAKE    = lcd.color( 90, 220, 130)
local C_HEAD     = lcd.color(160, 245, 175)
local C_FOOD     = lcd.color(255, 140, 100)
local C_BORDER   = lcd.color( 40,  44,  70)

-- ── Layout ────────────────────────────────────────────────
local HUD_H    = 12
local CELL     = 6
local PLAY_TOP = HUD_H + 2
local PLAY_BOT = H - 2
local COLS     = math.floor((W - 2) / CELL)
local ROWS     = math.floor((PLAY_BOT - PLAY_TOP) / CELL)
local PLAY_W   = COLS * CELL
local PLAY_H   = ROWS * CELL
local OFFSET_X = math.floor((W - PLAY_W) / 2)
local OFFSET_Y = PLAY_TOP

local SAVE_PATH = "/unigeek/games/snake.txt"

-- Direction lookup (1=right, 2=down, 3=left, 4=up)
local DX = { 1,  0, -1,  0 }
local DY = { 0,  1,  0, -1 }

-- ── State (declared once) ─────────────────────────────────
local snake             -- array of {x, y} cells; [1] is head
local dir
local pending_turn      -- nil | "left" | "right" (collapsed each tick)
local food_x, food_y
local food_eaten
local tick_interval
local frame
local highScore
local game_state        -- "play" | "paused" | "over"
local popup_drawn
local last_score_shown

math.randomseed(uni.millis())

-- ── Helpers ───────────────────────────────────────────────
local function loadHigh()
  if not sd.exists(SAVE_PATH) then return 0 end
  return tonumber(sd.read(SAVE_PATH) or "") or 0
end

local function saveHigh(n)
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
  sd.write(SAVE_PATH, tostring(n))
end

local function drawCell(x, y, color)
  lcd.rect(OFFSET_X + x * CELL, OFFSET_Y + y * CELL, CELL, CELL, color)
end

local function drawHUD()
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, string.format("LEN %-3d", #snake))
  local mid = string.format("ATE %-3d", food_eaten)
  lcd.textColor(C_GOOD, C_HUD_BG)
  local mw = lcd.textWidth(mid)
  lcd.print(math.floor((W - mw) / 2), 2, mid)
  local hi = string.format("HI %-3d", highScore)
  lcd.textColor(C_HI, C_HUD_BG)
  local hw = lcd.textWidth(hi)
  lcd.print(W - hw - 2, 2, hi)
end

local function drawSceneBackground()
  lcd.fillScreen(C_BG)
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_HUD_LINE)
  -- play-field border (1 px outside the cell grid)
  lcd.rect(OFFSET_X - 1, OFFSET_Y - 1, PLAY_W + 2, 1, C_BORDER)
  lcd.rect(OFFSET_X - 1, OFFSET_Y + PLAY_H, PLAY_W + 2, 1, C_BORDER)
  lcd.rect(OFFSET_X - 1, OFFSET_Y - 1, 1, PLAY_H + 2, C_BORDER)
  lcd.rect(OFFSET_X + PLAY_W, OFFSET_Y - 1, 1, PLAY_H + 2, C_BORDER)
end

local function isOccupied(x, y)
  for i = 1, #snake do
    if snake[i].x == x and snake[i].y == y then return true end
  end
  return false
end

local function spawnFood()
  for _ = 1, 200 do
    local fx = math.random(0, COLS - 1)
    local fy = math.random(0, ROWS - 1)
    if not isOccupied(fx, fy) then
      food_x, food_y = fx, fy
      return
    end
  end
  food_x, food_y = -1, -1
end

local function drawFood()
  if food_x >= 0 then drawCell(food_x, food_y, C_FOOD) end
end

local function drawSnake()
  for i = 2, #snake do
    drawCell(snake[i].x, snake[i].y, C_SNAKE)
  end
  drawCell(snake[1].x, snake[1].y, C_HEAD)
end

local function drawPlayField()
  lcd.rect(OFFSET_X, OFFSET_Y, PLAY_W, PLAY_H, C_BG)
  drawSnake()
  drawFood()
end

local function drawPausedOverlay()
  local boxW = math.min(W - 40, 140)
  local boxH = 38
  local bx = math.floor((W - boxW) / 2)
  local by = math.floor((H - boxH) / 2)
  lcd.fillRoundRect(bx, by, boxW, boxH, 4, C_HUD_BG)
  lcd.textSize(2)
  lcd.textColor(C_HI, C_HUD_BG)
  local t = "PAUSED"
  local tw = lcd.textWidth(t)
  lcd.print(bx + math.floor((boxW - tw) / 2), by + 4, t)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_HUD_BG)
  local h = "OK to resume"
  local hw = lcd.textWidth(h)
  lcd.print(bx + math.floor((boxW - hw) / 2), by + boxH - 12, h)
end

local function drawPopup()
  local boxW = math.min(W - 16, 200)
  local boxH = 72
  local bx = math.floor((W - boxW) / 2)
  local by = math.floor((H - boxH) / 2)
  lcd.rect(bx, by, boxW, boxH, C_HUD_BG)
  lcd.rect(bx, by, boxW, 1, C_DIM)
  lcd.rect(bx, by + boxH - 1, boxW, 1, C_DIM)
  lcd.rect(bx, by, 1, boxH, C_DIM)
  lcd.rect(bx + boxW - 1, by, 1, boxH, C_DIM)
  lcd.textSize(2)
  lcd.textColor(C_BAD, C_HUD_BG)
  local title = "GAME OVER"
  local tw = lcd.textWidth(title)
  lcd.print(bx + math.floor((boxW - tw) / 2), by + 8, title)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  local s = string.format("Length: %d   Ate: %d", #snake, food_eaten)
  local sw = lcd.textWidth(s)
  lcd.print(bx + math.floor((boxW - sw) / 2), by + 32, s)
  local hi = string.format("Best: %d", highScore)
  lcd.textColor(C_HI, C_HUD_BG)
  local hiw = lcd.textWidth(hi)
  lcd.print(bx + math.floor((boxW - hiw) / 2), by + 44, hi)
  lcd.textColor(C_DIM, C_HUD_BG)
  local hint = "OK: again   BACK: exit"
  local hw = lcd.textWidth(hint)
  lcd.print(bx + math.floor((boxW - hw) / 2), by + boxH - 14, hint)
end

local function applyTurn()
  if pending_turn == "left" then
    dir = dir - 1
    if dir == 0 then dir = 4 end
  elseif pending_turn == "right" then
    dir = dir + 1
    if dir == 5 then dir = 1 end
  end
  pending_turn = nil
end

local function moveSnake()
  applyTurn()
  local head = snake[1]
  local nx = head.x + DX[dir]
  local ny = head.y + DY[dir]

  if nx < 0 or nx >= COLS or ny < 0 or ny >= ROWS then
    game_state = "over"
    return
  end

  local growing  = (nx == food_x and ny == food_y)
  local check_to = growing and #snake or (#snake - 1)
  for i = 1, check_to do
    if snake[i].x == nx and snake[i].y == ny then
      game_state = "over"
      return
    end
  end

  table.insert(snake, 1, { x = nx, y = ny })

  drawCell(snake[2].x, snake[2].y, C_SNAKE)
  drawCell(nx, ny, C_HEAD)

  if growing then
    food_eaten = food_eaten + 1
    spawnFood()
    drawFood()
    uni.beep(1200, 30)
    tick_interval = math.max(2, 5 - math.floor(food_eaten / 5))
  else
    local tail = table.remove(snake)
    drawCell(tail.x, tail.y, C_BG)
  end
end

local function resetGame()
  local sx = math.floor(COLS / 2) - 1
  local sy = math.floor(ROWS / 2)
  snake = {
    { x = sx + 1, y = sy },
    { x = sx,     y = sy },
    { x = sx - 1, y = sy },
  }
  dir              = 1
  pending_turn     = nil
  food_eaten       = 0
  frame            = 0
  tick_interval    = 5
  game_state       = "play"
  popup_drawn      = false
  last_score_shown = -1
  spawnFood()
end

-- ── Init ──────────────────────────────────────────────────
highScore = loadHigh()
resetGame()
drawSceneBackground()
drawHUD()
last_score_shown = food_eaten
drawSnake()
drawFood()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if game_state == "play" then
    if btn == "up" then
      pending_turn = "left"
    elseif btn == "down" then
      pending_turn = "right"
    elseif btn == "ok" then
      game_state = "paused"
      drawPausedOverlay()
    end

    if game_state == "play" then
      frame = frame + 1
      if frame >= tick_interval then
        frame = 0
        moveSnake()
      end
      if food_eaten ~= last_score_shown then
        drawHUD()
        last_score_shown = food_eaten
      end
    end

  elseif game_state == "paused" then
    if btn == "ok" then
      drawPlayField()
      game_state = "play"
    end

  else
    if not popup_drawn then
      if food_eaten > highScore then
        highScore = food_eaten
        saveHigh(highScore)
        drawHUD()
      end
      drawPopup()
      popup_drawn = true
    end
    if btn == "ok" then
      drawSceneBackground()
      resetGame()
      drawHUD()
      last_score_shown = food_eaten
      drawSnake()
      drawFood()
    end
  end

  uni.delay(33)
end
