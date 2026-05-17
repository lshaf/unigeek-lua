-- invader.lua — Space Invader clone for the UniGeek Lua Runner
--   UP    / LEFT  : move ship left
--   DOWN  / RIGHT : move ship right
--   OK            : fire
--   BACK          : exit (also dismisses the Game Over popup)
--
-- Default UniGeek hardware only has up/down/ok/back, so the ship is moved
-- with up/down. Boards that have left/right still work too.
--
-- All movement uses overdraw — no lcd.clear()/fillScreen() inside the loop.
-- Helpers are declared before the main while-loop so no closures churn in
-- the hot path. High score persists to /unigeek/games/invader.txt.

local lcd = require("uni.lcd")
local nav = require("uni.nav")
local sd  = require("uni.sd")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG       = lcd.color(  5,   5,  20)
local C_HUD_BG   = lcd.color( 20,  20,  35)
local C_HUD_LINE = lcd.color( 60,  60,  90)
local C_TEXT     = lcd.color(220, 220, 240)
local C_DIM      = lcd.color(140, 140, 180)
local C_PLAYER   = lcd.color( 80, 220, 120)
local C_BULLET   = lcd.color(255, 235,  60)
local C_EBULLET  = lcd.color(255, 120, 120)
local C_HI       = lcd.color(255, 200,  60)
local C_INV1     = lcd.color(255, 120, 200)
local C_INV2     = lcd.color(120, 200, 255)
local C_INV3     = lcd.color(220, 200,  80)
local C_INV4     = lcd.color(160, 240, 120)

-- ── Layout ────────────────────────────────────────────────
local HUD_H    = 12
local PLAY_TOP = HUD_H + 1
local PLAY_BOT = H - 2

-- ── Dimensions ────────────────────────────────────────────
local INVADER_W   = 10
local INVADER_H   = 6
local GAP_X       = 4
local GAP_Y       = 4
local COLS        = (W < 180) and 6 or 8
local ROWS        = (H < 160) and 3 or 4
local PLAYER_W    = 14
local PLAYER_H    = 6
local PLAYER_SPD  = 8
local BULLET_W    = 2
local BULLET_H    = 4
local BULLET_SPD  = 6
local EBULLET_SPD = 3
local MAX_BULLETS  = 2
local MAX_EBULLETS = 3

local GRID_TOTAL_W = COLS * (INVADER_W + GAP_X) - GAP_X
local GRID_TOTAL_H = ROWS * (INVADER_H + GAP_Y) - GAP_Y
local TOTAL_INV    = ROWS * COLS

-- ── Save path ─────────────────────────────────────────────
local SAVE_PATH = "/unigeek/games/invader.txt"

-- ── State (declared once, mutated inside the loop) ────────
local score, lives, alive_count, frame, game_state
local player_x, player_x_prev, player_y
local grid_x, grid_y, grid_x_prev, grid_y_prev, grid_dx
local bullets, ebullets, invaders
local highScore = 0

math.randomseed(uni.millis())

-- ── Helpers (pre-allocated) ───────────────────────────────
local function rowColor(r)
  if r == 1 then return C_INV1
  elseif r == 2 then return C_INV2
  elseif r == 3 then return C_INV3
  else return C_INV4 end
end

local function rowPoints(r)
  if r == 1 then return 40
  elseif r == 2 then return 30
  elseif r == 3 then return 20
  else return 10 end
end

local function loadHigh()
  if not sd.exists(SAVE_PATH) then return 0 end
  local s = sd.read(SAVE_PATH) or ""
  return tonumber(s) or 0
end

local function saveHigh(n)
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
  sd.write(SAVE_PATH, tostring(n))
end

local function drawInvader(x, y, color)
  lcd.rect(x,                  y + 1, INVADER_W, INVADER_H - 2, color)
  lcd.rect(x + 2,              y,     2,         2,             color)
  lcd.rect(x + INVADER_W - 4,  y,     2,         2,             color)
  lcd.rect(x,                  y + INVADER_H - 1, 2, 1,         color)
  lcd.rect(x + INVADER_W - 2,  y + INVADER_H - 1, 2, 1,         color)
end

local function drawGrid()
  for r = 1, ROWS do
    for c = 1, COLS do
      if invaders[r][c] then
        local x = grid_x + (c - 1) * (INVADER_W + GAP_X)
        local y = grid_y + (r - 1) * (INVADER_H + GAP_Y)
        drawInvader(x, y, rowColor(r))
      end
    end
  end
end

local function eraseGridArea(gx, gy)
  lcd.rect(gx, gy, GRID_TOTAL_W, GRID_TOTAL_H, C_BG)
end

local function drawPlayer(x)
  lcd.rect(x,                                 player_y + 2, PLAYER_W,     PLAYER_H - 2, C_PLAYER)
  lcd.rect(x + 2,                             player_y + 1, PLAYER_W - 4, 1,            C_PLAYER)
  lcd.rect(x + math.floor(PLAYER_W / 2) - 1,  player_y - 2, 2,            3,            C_PLAYER)
end

local function erasePlayer(x)
  lcd.rect(x, player_y - 2, PLAYER_W, PLAYER_H + 2, C_BG)
end

local function fireBullet()
  for i = 1, MAX_BULLETS do
    local b = bullets[i]
    if not b.alive then
      b.x = player_x + math.floor(PLAYER_W / 2) - math.floor(BULLET_W / 2)
      b.y = player_y - BULLET_H - 2
      b.x_prev = b.x
      b.y_prev = b.y
      b.alive  = true
      uni.beep(1400, 18)
      return
    end
  end
end

local function fireEnemyBullet()
  if alive_count == 0 then return end
  for try = 1, 6 do
    local c = math.random(1, COLS)
    for r = ROWS, 1, -1 do
      if invaders[r][c] then
        for i = 1, MAX_EBULLETS do
          local eb = ebullets[i]
          if not eb.alive then
            eb.x = grid_x + (c - 1) * (INVADER_W + GAP_X) + math.floor(INVADER_W / 2)
            eb.y = grid_y + (r - 1) * (INVADER_H + GAP_Y) + INVADER_H + 1
            eb.x_prev = eb.x
            eb.y_prev = eb.y
            eb.alive  = true
            return
          end
        end
        return
      end
    end
  end
end

local function stepGrid()
  local left_col, right_col = nil, nil
  for c = 1, COLS do
    for r = 1, ROWS do
      if invaders[r][c] then
        if left_col == nil then left_col = c end
        right_col = c
        break
      end
    end
  end
  if left_col == nil then return end

  local left_edge  = grid_x + (left_col - 1)  * (INVADER_W + GAP_X)
  local right_edge = grid_x + (right_col - 1) * (INVADER_W + GAP_X) + INVADER_W

  grid_x_prev = grid_x
  grid_y_prev = grid_y

  if right_edge + grid_dx > W - 2 or left_edge + grid_dx < 2 then
    grid_dx = -grid_dx
    grid_y  = grid_y + INVADER_H + GAP_Y
  else
    grid_x  = grid_x + grid_dx
  end

  eraseGridArea(grid_x_prev, grid_y_prev)
  drawGrid()
  uni.beep(180, 12)

  local bottom_y = grid_y + (ROWS - 1) * (INVADER_H + GAP_Y) + INVADER_H
  if bottom_y >= player_y then
    game_state = "over"
  end
end

local function checkCollisions()
  for i = 1, MAX_BULLETS do
    local b = bullets[i]
    if b.alive then
      local rel_x = b.x - grid_x
      local rel_y = b.y - grid_y
      if rel_x >= 0 and rel_y >= 0 then
        local c = math.floor(rel_x / (INVADER_W + GAP_X)) + 1
        local r = math.floor(rel_y / (INVADER_H + GAP_Y)) + 1
        if c >= 1 and c <= COLS and r >= 1 and r <= ROWS and invaders[r][c] then
          local ix = grid_x + (c - 1) * (INVADER_W + GAP_X)
          local iy = grid_y + (r - 1) * (INVADER_H + GAP_Y)
          if b.x + BULLET_W > ix and b.x < ix + INVADER_W
             and b.y + BULLET_H > iy and b.y < iy + INVADER_H then
            invaders[r][c] = false
            alive_count = alive_count - 1
            score = score + rowPoints(r)
            lcd.rect(ix, iy, INVADER_W, INVADER_H, C_BG)
            lcd.rect(b.x_prev, b.y_prev, BULLET_W, BULLET_H, C_BG)
            lcd.rect(b.x,      b.y,      BULLET_W, BULLET_H, C_BG)
            b.alive = false
            uni.beep(440, 25)
          end
        end
      end
    end
  end

  for i = 1, MAX_EBULLETS do
    local eb = ebullets[i]
    if eb.alive then
      if eb.x + BULLET_W > player_x and eb.x < player_x + PLAYER_W
         and eb.y + BULLET_H > player_y - 2 and eb.y < player_y + PLAYER_H then
        lives = lives - 1
        lcd.rect(eb.x_prev, eb.y_prev, BULLET_W, BULLET_H, C_BG)
        lcd.rect(eb.x,      eb.y,      BULLET_W, BULLET_H, C_BG)
        eb.alive = false
        uni.beep(120, 200)
        if lives <= 0 then
          game_state = "over"
        end
      end
    end
  end
end

local function drawHUD()
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, string.format("SCORE %-5d", score))

  local lStr = string.format("LIVES %d", math.max(0, lives))
  lcd.textColor(C_PLAYER, C_HUD_BG)
  local lw = lcd.textWidth(lStr)
  lcd.print(W - lw - 2, 2, lStr)
end

local function drawGameOver(win)
  local boxW = math.min(W - 16, 200)
  local boxH = 76
  local bx = math.floor((W - boxW) / 2)
  local by = math.floor((H - boxH) / 2)
  lcd.rect(bx, by, boxW, boxH, C_HUD_BG)
  lcd.rect(bx, by, boxW, 1, C_DIM)
  lcd.rect(bx, by + boxH - 1, boxW, 1, C_DIM)
  lcd.rect(bx, by, 1, boxH, C_DIM)
  lcd.rect(bx + boxW - 1, by, 1, boxH, C_DIM)

  lcd.textSize(2)
  local title = win and "YOU WIN!" or "GAME OVER"
  lcd.textColor(win and C_PLAYER or C_EBULLET, C_HUD_BG)
  local tw = lcd.textWidth(title)
  lcd.print(bx + math.floor((boxW - tw) / 2), by + 8, title)

  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  local s = string.format("Score: %d", score)
  local sw = lcd.textWidth(s)
  lcd.print(bx + math.floor((boxW - sw) / 2), by + 34, s)

  local hi = string.format("High: %d", highScore)
  lcd.textColor(C_HI, C_HUD_BG)
  local hiw = lcd.textWidth(hi)
  lcd.print(bx + math.floor((boxW - hiw) / 2), by + 46, hi)

  lcd.textColor(C_DIM, C_HUD_BG)
  local hint = "OK: again   BACK: exit"
  local hw = lcd.textWidth(hint)
  lcd.print(bx + math.floor((boxW - hw) / 2), by + boxH - 14, hint)
end

local function resetGame()
  score        = 0
  lives        = 3
  alive_count  = TOTAL_INV
  frame        = 0
  game_state   = "play"

  invaders = {}
  for r = 1, ROWS do
    invaders[r] = {}
    for c = 1, COLS do invaders[r][c] = true end
  end

  grid_x      = math.floor((W - GRID_TOTAL_W) / 2)
  grid_y      = PLAY_TOP + 8
  grid_x_prev = grid_x
  grid_y_prev = grid_y
  grid_dx     = 4

  player_x      = math.floor((W - PLAYER_W) / 2)
  player_x_prev = player_x
  player_y      = PLAY_BOT - PLAYER_H

  bullets = {}
  for i = 1, MAX_BULLETS do
    bullets[i] = { x = 0, y = 0, x_prev = 0, y_prev = 0, alive = false }
  end
  ebullets = {}
  for i = 1, MAX_EBULLETS do
    ebullets[i] = { x = 0, y = 0, x_prev = 0, y_prev = 0, alive = false }
  end
end

local function drawSceneBackground()
  lcd.fillScreen(C_BG)
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_HUD_LINE)
end

-- ── Init ──────────────────────────────────────────────────
highScore = loadHigh()
resetGame()
drawSceneBackground()
drawGrid()
drawPlayer(player_x)
drawHUD()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if game_state == "play" then
    frame = frame + 1

    if btn == "up" or btn == "left" then
      player_x_prev = player_x
      player_x = math.max(2, player_x - PLAYER_SPD)
    elseif btn == "down" or btn == "right" then
      player_x_prev = player_x
      player_x = math.min(W - PLAYER_W - 2, player_x + PLAYER_SPD)
    elseif btn == "ok" then
      fireBullet()
    end

    for i = 1, MAX_BULLETS do
      local b = bullets[i]
      if b.alive then
        b.x_prev = b.x
        b.y_prev = b.y
        b.y = b.y - BULLET_SPD
        if b.y + BULLET_H < PLAY_TOP then
          b.alive = false
          lcd.rect(b.x_prev, b.y_prev, BULLET_W, BULLET_H, C_BG)
        end
      end
    end

    for i = 1, MAX_EBULLETS do
      local eb = ebullets[i]
      if eb.alive then
        eb.x_prev = eb.x
        eb.y_prev = eb.y
        eb.y = eb.y + EBULLET_SPD
        if eb.y > PLAY_BOT then
          eb.alive = false
          lcd.rect(eb.x_prev, eb.y_prev, BULLET_W, BULLET_H, C_BG)
        end
      end
    end

    local interval = math.max(6, 30 - math.floor((TOTAL_INV - alive_count) / 2))
    if frame % interval == 0 then
      stepGrid()
    end

    if math.random(1, 50) == 1 then
      fireEnemyBullet()
    end

    checkCollisions()

    if player_x ~= player_x_prev then
      erasePlayer(player_x_prev)
      drawPlayer(player_x)
      player_x_prev = player_x
    end

    for i = 1, MAX_BULLETS do
      local b = bullets[i]
      if b.alive then
        if b.x_prev ~= b.x or b.y_prev ~= b.y then
          lcd.rect(b.x_prev, b.y_prev, BULLET_W, BULLET_H, C_BG)
        end
        lcd.rect(b.x, b.y, BULLET_W, BULLET_H, C_BULLET)
        b.x_prev = b.x
        b.y_prev = b.y
      end
    end
    for i = 1, MAX_EBULLETS do
      local eb = ebullets[i]
      if eb.alive then
        if eb.x_prev ~= eb.x or eb.y_prev ~= eb.y then
          lcd.rect(eb.x_prev, eb.y_prev, BULLET_W, BULLET_H, C_BG)
        end
        lcd.rect(eb.x, eb.y, BULLET_W, BULLET_H, C_EBULLET)
        eb.x_prev = eb.x
        eb.y_prev = eb.y
      end
    end

    drawHUD()

    if alive_count == 0 then
      game_state = "win"
      uni.beep(880, 80)
    end

    if game_state ~= "play" then
      if score > highScore then
        highScore = score
        saveHigh(highScore)
      end
      drawGameOver(game_state == "win")
    end
  else
    if btn == "ok" then
      resetGame()
      drawSceneBackground()
      drawGrid()
      drawPlayer(player_x)
      drawHUD()
    end
  end

  uni.delay(33)
end
