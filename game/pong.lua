--[[
@title Pong
@description Classic paddle game against the AI — out-rally the opponent to score.
@category Game
@author lshaf
]]
-- pong.lua — Pong vs AI
-- Classic paddle game. You are the left paddle, AI is the right.
-- Ball direction after a hit varies with where it strikes the paddle
-- (centre = straight, edges = steeper angle). First to 5 wins.
--
--   UP   : move your paddle up
--   DOWN : move your paddle down
--   OK   : serve (after a point or on first launch) / restart on popup
--   BACK : exit (also dismisses the Game Over popup)
--
-- Lifetime wins/losses persist as JSON in /unigeek/games/pong.txt.

local lcd  = require("uni.lcd")
local nav  = require("uni.nav")
local sd   = require("uni.sd")
local json = require("uni.json")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG       = lcd.color(  5,   8,  20)
local C_HUD_BG   = lcd.color( 22,  22,  38)
local C_HUD_LINE = lcd.color( 60,  60,  90)
local C_TEXT     = lcd.color(220, 220, 240)
local C_DIM      = lcd.color(140, 140, 180)
local C_HI       = lcd.color(255, 200,  60)
local C_GOOD     = lcd.color(120, 220, 130)
local C_BAD      = lcd.color(255, 110, 110)
local C_PLAYER   = lcd.color(120, 220, 255)
local C_AI       = lcd.color(255, 140, 100)
local C_BALL     = lcd.color(255, 255, 200)
local C_CENTER   = lcd.color( 50,  50,  80)

-- ── Layout ────────────────────────────────────────────────
local HUD_H     = 12
local HINT_Y    = H - 12
local COURT_TOP = HUD_H + 2
local COURT_BOT = HINT_Y - 2
local COURT_H   = COURT_BOT - COURT_TOP

local PADDLE_W      = 3
local PADDLE_H      = math.max(20, math.min(36, math.floor(COURT_H * 0.22)))
local BALL_SIZE     = 4
local PLAYER_X      = 4
local AI_X          = W - 4 - PADDLE_W
local PLAYER_SPEED  = 8
local AI_SPEED      = 2
local BALL_VX_BASE  = 2
local WIN_SCORE     = 5
local SAVE_PATH     = "/unigeek/games/pong.txt"

-- ── State (declared once) ─────────────────────────────────
local player_y, player_y_prev
local ai_y,     ai_y_prev
local ball_x,   ball_y
local ball_x_prev, ball_y_prev
local ball_vx, ball_vy
local player_score, ai_score
local game_state            -- "serve" | "play" | "over"
local winner
local stats
local popup_drawn

math.randomseed(uni.millis())

-- ── Helpers ───────────────────────────────────────────────
local function loadStats()
  if not sd.exists(SAVE_PATH) then return { wins = 0, losses = 0 } end
  local raw = sd.read(SAVE_PATH) or ""
  local data = json.decode(raw)
  if not data then return { wins = 0, losses = 0 } end
  data.wins   = data.wins   or 0
  data.losses = data.losses or 0
  return data
end

local function saveStats()
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
  sd.write(SAVE_PATH, json.encode(stats))
end

local function drawCenterLine()
  local x = math.floor(W / 2)
  for y = COURT_TOP + 4, COURT_BOT - 4, 8 do
    lcd.rect(x, y, 1, 4, C_CENTER)
  end
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_HUD_LINE)
  lcd.textSize(1)
  local p_label = string.format("YOU %d", player_score)
  local a_label = string.format("%d AI", ai_score)
  local mid     = string.format("W/L %d/%d", stats.wins, stats.losses)
  lcd.textColor(C_PLAYER, C_HUD_BG)
  lcd.print(2, 2, p_label)
  lcd.textColor(C_AI, C_HUD_BG)
  local aw = lcd.textWidth(a_label)
  lcd.print(W - aw - 2, 2, a_label)
  lcd.textColor(C_DIM, C_HUD_BG)
  local mw = lcd.textWidth(mid)
  lcd.print(math.floor((W - mw) / 2), 2, mid)
end

local function drawHint(text)
  lcd.rect(0, HINT_Y, W, 10, C_BG)
  if text == "" then return end
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local sw = lcd.textWidth(text)
  lcd.print(math.floor((W - sw) / 2), HINT_Y, text)
end

local function drawPaddle(x, y, color)
  lcd.rect(x, y, PADDLE_W, PADDLE_H, color)
end

local function erasePaddle(x, y)
  lcd.rect(x, y, PADDLE_W, PADDLE_H, C_BG)
end

local function drawBall(x, y)
  lcd.rect(x, y, BALL_SIZE, BALL_SIZE, C_BALL)
end

local function eraseBall(x, y)
  lcd.rect(x, y, BALL_SIZE, BALL_SIZE, C_BG)
end

local function resetBall(direction)
  ball_x = math.floor((W - BALL_SIZE) / 2)
  ball_y = math.floor(COURT_TOP + (COURT_H - BALL_SIZE) / 2)
  ball_vx = BALL_VX_BASE * direction
  ball_vy = (math.random(0, 1) == 0) and 2 or -2
  ball_x_prev = ball_x
  ball_y_prev = ball_y
end

local function startMatch()
  player_y      = math.floor(COURT_TOP + (COURT_H - PADDLE_H) / 2)
  ai_y          = player_y
  player_y_prev = player_y
  ai_y_prev     = ai_y
  player_score  = 0
  ai_score      = 0
  game_state    = "serve"
  winner        = nil
  popup_drawn   = false
  resetBall((math.random(0, 1) == 0) and 1 or -1)
end

local function drawScene()
  lcd.fillScreen(C_BG)
  drawHUD()
  drawCenterLine()
  drawPaddle(PLAYER_X, player_y, C_PLAYER)
  drawPaddle(AI_X, ai_y, C_AI)
  drawBall(ball_x, ball_y)
end

local function drawPopup()
  local boxW = math.min(W - 16, 220)
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
  if winner == "player" then title, color = "YOU WIN!", C_GOOD
  else                       title, color = "AI WINS",  C_BAD end
  lcd.textColor(color, C_HUD_BG)
  local tw = lcd.textWidth(title)
  lcd.print(bx + math.floor((boxW - tw) / 2), by + 8, title)

  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  local s = string.format("Final: %d - %d", player_score, ai_score)
  local sw = lcd.textWidth(s)
  lcd.print(bx + math.floor((boxW - sw) / 2), by + 32, s)

  lcd.textColor(C_HI, C_HUD_BG)
  local r = string.format("Record: %d W / %d L", stats.wins, stats.losses)
  local rw = lcd.textWidth(r)
  lcd.print(bx + math.floor((boxW - rw) / 2), by + 44, r)

  lcd.textColor(C_DIM, C_HUD_BG)
  local hint = "OK: again   BACK: exit"
  local hw = lcd.textWidth(hint)
  lcd.print(bx + math.floor((boxW - hw) / 2), by + boxH - 14, hint)
end

local function paddleHit(paddle_y, hit_center_y)
  local rel = (hit_center_y - paddle_y) / PADDLE_H   -- 0..1
  local dy  = (rel - 0.5) * 6                        -- -3..+3
  ball_vy   = math.floor(dy + (dy >= 0 and 0.5 or -0.5))
  if ball_vy == 0 then
    ball_vy = (math.random(0, 1) == 0) and 1 or -1
  end
end

local function updateAI()
  if ball_vx <= 0 then return end
  ai_y_prev = ai_y
  local center = ai_y + math.floor(PADDLE_H / 2)
  if ball_y + math.floor(BALL_SIZE / 2) < center - 3 then
    ai_y = math.max(COURT_TOP, ai_y - AI_SPEED)
  elseif ball_y + math.floor(BALL_SIZE / 2) > center + 3 then
    ai_y = math.min(COURT_BOT - PADDLE_H, ai_y + AI_SPEED)
  end
end

local function scoreFor(side)
  if side == "player" then
    player_score = player_score + 1
    uni.beep(1000, 60)
  else
    ai_score = ai_score + 1
    uni.beep(220, 80)
  end

  if player_score >= WIN_SCORE then
    winner       = "player"
    stats.wins   = stats.wins + 1
    saveStats()
    game_state   = "over"
    return
  end
  if ai_score >= WIN_SCORE then
    winner       = "ai"
    stats.losses = stats.losses + 1
    saveStats()
    game_state   = "over"
    return
  end

  -- Recentre paddles and reset ball, serve toward the loser.
  erasePaddle(PLAYER_X, player_y)
  erasePaddle(AI_X, ai_y)
  player_y = math.floor(COURT_TOP + (COURT_H - PADDLE_H) / 2)
  ai_y     = player_y
  player_y_prev = player_y
  ai_y_prev     = ai_y
  resetBall(side == "player" and 1 or -1)
  drawPaddle(PLAYER_X, player_y, C_PLAYER)
  drawPaddle(AI_X, ai_y, C_AI)
  drawCenterLine()
  drawBall(ball_x, ball_y)
  drawHUD()
  game_state = "serve"
end

local function updateBall()
  ball_x_prev = ball_x
  ball_y_prev = ball_y
  ball_x = ball_x + ball_vx
  ball_y = ball_y + ball_vy

  -- Top / bottom walls
  if ball_y <= COURT_TOP then
    ball_y  = COURT_TOP
    ball_vy = -ball_vy
    uni.beep(420, 12)
  elseif ball_y + BALL_SIZE >= COURT_BOT then
    ball_y  = COURT_BOT - BALL_SIZE
    ball_vy = -ball_vy
    uni.beep(420, 12)
  end

  -- Player paddle
  if ball_vx < 0 and ball_x <= PLAYER_X + PADDLE_W
     and ball_x + BALL_SIZE >= PLAYER_X
     and ball_y + BALL_SIZE > player_y and ball_y < player_y + PADDLE_H then
    ball_x  = PLAYER_X + PADDLE_W
    ball_vx = -ball_vx
    paddleHit(player_y, ball_y + math.floor(BALL_SIZE / 2))
    uni.beep(900, 18)
  end

  -- AI paddle
  if ball_vx > 0 and ball_x + BALL_SIZE >= AI_X
     and ball_x <= AI_X + PADDLE_W
     and ball_y + BALL_SIZE > ai_y and ball_y < ai_y + PADDLE_H then
    ball_x  = AI_X - BALL_SIZE
    ball_vx = -ball_vx
    paddleHit(ai_y, ball_y + math.floor(BALL_SIZE / 2))
    uni.beep(900, 18)
  end

  -- Goal lines
  if ball_x + BALL_SIZE < 0 then
    eraseBall(ball_x_prev, ball_y_prev)
    scoreFor("ai")
  elseif ball_x > W then
    eraseBall(ball_x_prev, ball_y_prev)
    scoreFor("player")
  end
end

-- ── Init ──────────────────────────────────────────────────
stats = loadStats()
startMatch()
drawScene()
drawHint("UP/DOWN paddle    OK serve    BACK exit")

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if game_state == "serve" then
    if btn == "up" then
      player_y_prev = player_y
      player_y = math.max(COURT_TOP, player_y - PLAYER_SPEED)
      if player_y ~= player_y_prev then
        erasePaddle(PLAYER_X, player_y_prev)
        drawPaddle(PLAYER_X, player_y, C_PLAYER)
      end
    elseif btn == "down" then
      player_y_prev = player_y
      player_y = math.min(COURT_BOT - PADDLE_H, player_y + PLAYER_SPEED)
      if player_y ~= player_y_prev then
        erasePaddle(PLAYER_X, player_y_prev)
        drawPaddle(PLAYER_X, player_y, C_PLAYER)
      end
    elseif btn == "ok" then
      game_state = "play"
      uni.beep(1200, 30)
    end

  elseif game_state == "play" then
    if btn == "up" then
      player_y_prev = player_y
      player_y = math.max(COURT_TOP, player_y - PLAYER_SPEED)
    elseif btn == "down" then
      player_y_prev = player_y
      player_y = math.min(COURT_BOT - PADDLE_H, player_y + PLAYER_SPEED)
    end

    updateAI()
    updateBall()

    if player_y ~= player_y_prev then
      erasePaddle(PLAYER_X, player_y_prev)
      drawPaddle(PLAYER_X, player_y, C_PLAYER)
      player_y_prev = player_y
    end
    if ai_y ~= ai_y_prev then
      erasePaddle(AI_X, ai_y_prev)
      drawPaddle(AI_X, ai_y, C_AI)
      ai_y_prev = ai_y
    end

    if game_state == "play" then
      eraseBall(ball_x_prev, ball_y_prev)
      drawBall(ball_x, ball_y)
    end

  else
    if not popup_drawn then
      drawPopup()
      popup_drawn = true
    end
    if btn == "ok" then
      startMatch()
      drawScene()
      drawHint("UP/DOWN paddle    OK serve    BACK exit")
    end
  end

  uni.delay(33)
end
