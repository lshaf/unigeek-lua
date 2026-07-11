--[[
@title Coin Flip
@description Flip a virtual coin with a short heads/tails animation.
@category Utility
@author lshaf
]]
-- coin-flip.lua — Coin Flip
-- Press OK to flip a coin. A short animation cycles heads/tails before
-- settling on the result. Running tally and a strip of the last flips
-- live in the lower half of the screen.
--
--   OK   : flip
--   BACK : exit (also aborts an in-progress flip animation)

local lcd = require("uni.lcd")
local nav = require("uni.nav")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG       = lcd.color( 10,  12,  28)
local C_HUD_BG   = lcd.color( 22,  22,  38)
local C_TEXT     = lcd.color(220, 220, 240)
local C_DIM      = lcd.color(140, 140, 180)
local C_HEADS    = lcd.color(255, 200,  60)
local C_TAILS    = lcd.color(150, 200, 255)
local C_OUTLINE  = lcd.color( 80,  80, 110)

-- ── Layout ────────────────────────────────────────────────
local HUD_H      = 12
local COIN_R     = math.min(36, math.max(20, math.floor(H * 0.22)))
local COIN_CX    = math.floor(W / 2)
local COIN_CY    = HUD_H + COIN_R + 8
local TEXT_SIZE  = (COIN_R >= 28) and 4 or 3
local STATS_Y    = COIN_CY + COIN_R + 8
local HISTORY_Y  = STATS_Y + 12
local HINT_Y     = H - 12
local FLIP_FRAMES = 14
local MAX_HISTORY = 12

-- ── State ─────────────────────────────────────────────────
local count_h = 0
local count_t = 0
local history = {}    -- array of "H" or "T"

math.randomseed(uni.millis())

-- ── Helpers ───────────────────────────────────────────────
local function drawCoin(face)
  local fill, label = C_DIM, "?"
  if face == "heads"  then fill, label = C_HEADS, "H" end
  if face == "tails"  then fill, label = C_TAILS, "T" end
  lcd.fillCircle(COIN_CX, COIN_CY, COIN_R, fill)
  lcd.circle(COIN_CX, COIN_CY, COIN_R, C_OUTLINE)
  lcd.textSize(TEXT_SIZE)
  lcd.textColor(C_BG)
  local tw = lcd.textWidth(label)
  local th = TEXT_SIZE * 8
  lcd.print(COIN_CX - math.floor(tw / 2), COIN_CY - math.floor(th / 2), label)
  lcd.textSize(1)
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Coin Flip")
  local total = count_h + count_t
  if total > 0 then
    local s = string.format("%d flips", total)
    lcd.textColor(C_DIM, C_HUD_BG)
    local w = lcd.textWidth(s)
    lcd.print(W - w - 2, 2, s)
  end
end

local function drawStats()
  lcd.rect(0, STATS_Y, W, 10, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local s = string.format("H: %d   T: %d", count_h, count_t)
  local w = lcd.textWidth(s)
  lcd.print(math.floor((W - w) / 2), STATS_Y, s)
end

local function drawHistory()
  lcd.rect(0, HISTORY_Y, W, 10, C_BG)
  if #history == 0 then return end
  local R = 3
  local GAP = 2
  local entries = math.min(#history, MAX_HISTORY)
  local total_w = entries * (R * 2 + GAP) - GAP
  local x0 = math.floor((W - total_w) / 2)
  for i = 0, entries - 1 do
    local idx = #history - (entries - 1 - i)
    local face = history[idx]
    local color = (face == "H") and C_HEADS or C_TAILS
    lcd.fillCircle(x0 + i * (R * 2 + GAP) + R, HISTORY_Y + R, R, color)
  end
end

local function drawHints()
  lcd.textSize(1)
  lcd.rect(0, HINT_Y, W, 10, C_BG)
  lcd.textColor(C_DIM, C_BG)
  local s = "OK: flip    BACK: exit"
  local w = lcd.textWidth(s)
  lcd.print(math.floor((W - w) / 2), HINT_Y, s)
end

-- Returns "heads" / "tails", or nil if BACK was pressed during animation.
local function flipAnimation()
  local final = (math.random(0, 1) == 0) and "heads" or "tails"
  for i = 1, FLIP_FRAMES do
    if nav.btn() == "back" then return nil end
    local f = ((i % 2) == 0) and "heads" or "tails"
    drawCoin(f)
    uni.beep(450 + i * 40, 16)
    uni.delay(50)
  end
  drawCoin(final)
  uni.beep(1300, 80)
  return final
end

-- ── Init ──────────────────────────────────────────────────
lcd.fillScreen(C_BG)
drawHUD()
drawCoin(nil)
drawStats()
drawHistory()
drawHints()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if btn == "ok" then
    local r = flipAnimation()
    if r == nil then break end
    if r == "heads" then
      count_h = count_h + 1
      history[#history + 1] = "H"
    else
      count_t = count_t + 1
      history[#history + 1] = "T"
    end
    if #history > MAX_HISTORY * 2 then table.remove(history, 1) end
    drawStats()
    drawHistory()
    drawHUD()
  end

  uni.delay(33)
end
