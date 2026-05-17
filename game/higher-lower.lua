-- higher-lower.lua — Higher / Lower
-- A card with a value 1..13 is shown. Guess if the next card will be
-- HIGHER (UP) or LOWER (DOWN). Ties count as correct. A wrong guess
-- ends the run; the longest streak is saved as the best score.
--
--   UP   : next card will be higher
--   DOWN : next card will be lower
--   OK   : start a new game from the Game Over popup
--   BACK : exit
--
-- Cards 1, 11, 12, 13 show as A, J, Q, K. Half the deck shows red,
-- half black — purely cosmetic; the comparison is on the value.
--
-- High score persists to /unigeek/games/higher-lower.txt.

local lcd = require("uni.lcd")
local nav = require("uni.nav")
local sd  = require("uni.sd")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG          = lcd.color( 10,  10,  30)
local C_HUD_BG      = lcd.color( 22,  22,  38)
local C_TEXT        = lcd.color(220, 220, 240)
local C_DIM         = lcd.color(140, 140, 180)
local C_HI          = lcd.color(255, 200,  60)
local C_OK          = lcd.color( 80, 220, 120)
local C_BAD         = lcd.color(255, 110, 110)
local C_CARD        = lcd.color(245, 245, 250)
local C_CARD_SHADOW = lcd.color(  0,   0,  10)
local C_CARD_RED    = lcd.color(210,  40,  40)
local C_CARD_BLK    = lcd.color( 18,  18,  30)

local SAVE_PATH = "/unigeek/games/higher-lower.txt"

-- ── Layout ────────────────────────────────────────────────
local HUD_H         = 12
local CARD_W        = math.min(76, math.max(48, math.floor(W * 0.32)))
local CARD_H        = math.min(108, math.max(60, math.floor(H * 0.55)))
local CARD_X        = math.floor((W - CARD_W) / 2)
local CARD_Y        = HUD_H + math.max(4, math.floor((H - HUD_H - CARD_H - 28) / 2))
local CARD_NUM_SIZE = (CARD_H >= 96) and 5 or 4
local MSG_Y         = math.min(H - 26, CARD_Y + CARD_H + 4)
local HINT_Y        = H - 12

-- ── State ─────────────────────────────────────────────────
local current_card, current_color
local score      = 0
local highScore  = 0
local game_state                 -- "guessing" | "over"
local last_msg, last_msg_color
local popup_drawn

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

local function newCard()
  return math.random(1, 13), (math.random(0, 1) == 0) and "red" or "black"
end

local function cardLabel(n)
  if n == 1  then return "A" end
  if n == 11 then return "J" end
  if n == 12 then return "Q" end
  if n == 13 then return "K" end
  return tostring(n)
end

local function cardFG(col)
  return (col == "red") and C_CARD_RED or C_CARD_BLK
end

local function drawCard(n, col)
  lcd.rect(CARD_X - 2, CARD_Y - 2, CARD_W + 6, CARD_H + 6, C_BG)
  lcd.fillRoundRect(CARD_X + 2, CARD_Y + 2, CARD_W, CARD_H, 6, C_CARD_SHADOW)
  lcd.fillRoundRect(CARD_X,     CARD_Y,     CARD_W, CARD_H, 6, C_CARD)

  local label = cardLabel(n)
  local fg    = cardFG(col)

  lcd.textSize(CARD_NUM_SIZE)
  lcd.textColor(fg, C_CARD)
  local bw = lcd.textWidth(label)
  local bh = CARD_NUM_SIZE * 8
  lcd.print(CARD_X + math.floor((CARD_W - bw) / 2),
            CARD_Y + math.floor((CARD_H - bh) / 2),
            label)

  lcd.textSize(1)
  lcd.print(CARD_X + 4, CARD_Y + 4, label)
  local cw = lcd.textWidth(label)
  lcd.print(CARD_X + CARD_W - cw - 4, CARD_Y + CARD_H - 12, label)
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, string.format("STREAK %-3d", score))
  local hiStr = string.format("BEST %-3d", highScore)
  lcd.textColor(C_HI, C_HUD_BG)
  local hw = lcd.textWidth(hiStr)
  lcd.print(W - hw - 2, 2, hiStr)
end

local function drawMsg(text, color)
  lcd.rect(0, MSG_Y, W, 10, C_BG)
  if text == "" then return end
  lcd.textSize(1)
  lcd.textColor(color, C_BG)
  local w = lcd.textWidth(text)
  lcd.print(math.floor((W - w) / 2), MSG_Y, text)
end

local function drawHints()
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.rect(0, HINT_Y, W, 10, C_BG)
  local hint = "UP higher   DOWN lower   BACK exit"
  if lcd.textWidth(hint) > W then hint = "UP higher  DOWN lower" end
  if lcd.textWidth(hint) > W then hint = "UP / DOWN to guess" end
  local w = lcd.textWidth(hint)
  lcd.print(math.floor((W - w) / 2), HINT_Y, hint)
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
  local s = string.format("Streak: %d", score)
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

local function resetGame()
  score                       = 0
  current_card, current_color = newCard()
  last_msg                    = ""
  last_msg_color              = C_OK
  game_state                  = "guessing"
  popup_drawn                 = false
end

local function processGuess(direction)
  local next_card, next_color = newCard()
  local prev = current_card

  local correct
  if next_card == prev then
    correct = true
  elseif direction == "higher" then
    correct = next_card > prev
  else
    correct = next_card < prev
  end

  current_card, current_color = next_card, next_color

  if correct then
    score = score + 1
    if next_card == prev then
      last_msg = string.format("tie at %s - keep going", cardLabel(prev))
    else
      last_msg = string.format("yes! %s -> %s", cardLabel(prev), cardLabel(next_card))
    end
    last_msg_color = C_OK
    uni.beep(880 + math.min(score, 16) * 30, 45)
  else
    last_msg       = string.format("miss: %s -> %s", cardLabel(prev), cardLabel(next_card))
    last_msg_color = C_BAD
    game_state     = "over"
    if score > highScore then
      highScore = score
      saveHigh(highScore)
    end
    uni.beep(160, 200)
  end
end

-- ── Init ──────────────────────────────────────────────────
highScore = loadHigh()
resetGame()
lcd.fillScreen(C_BG)
drawHUD()
drawCard(current_card, current_color)
drawMsg(last_msg, last_msg_color)
drawHints()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if game_state == "guessing" then
    if btn == "up" or btn == "down" then
      processGuess((btn == "up") and "higher" or "lower")
      drawHUD()
      drawCard(current_card, current_color)
      drawMsg(last_msg, last_msg_color)
    end
  else
    if not popup_drawn then
      drawPopup()
      popup_drawn = true
    end
    if btn == "ok" then
      lcd.fillScreen(C_BG)
      resetGame()
      drawHUD()
      drawCard(current_card, current_color)
      drawMsg(last_msg, last_msg_color)
      drawHints()
    end
  end

  uni.delay(33)
end
