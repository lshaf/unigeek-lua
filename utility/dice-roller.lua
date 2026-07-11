--[[
@title Dice Roller
@description Roll a die of your chosen type and see the result with a rolling animation.
@category Utility
@author lshaf
]]
-- dice-roller.lua — Dice Roller
-- Pick a die type, roll it, see the result big in the centre with a
-- short rolling animation. The most recent rolls collect in a strip
-- at the bottom.
--
--   UP   : previous die type (cycles)
--   DOWN : next die type (cycles)
--   OK   : roll the current die
--   BACK : exit (also aborts an in-progress roll animation)

local lcd = require("uni.lcd")
local nav = require("uni.nav")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG     = lcd.color( 10,  12,  28)
local C_HUD_BG = lcd.color( 22,  22,  38)
local C_TEXT   = lcd.color(220, 220, 240)
local C_DIM    = lcd.color(140, 140, 180)
local C_DIE    = lcd.color(255, 180,  80)
local C_RESULT = lcd.color( 80, 220, 255)
local C_RESULT_DIM = lcd.color( 60, 110, 140)

-- ── Dice ──────────────────────────────────────────────────
local DICE = {
  { n = 4,   label = "d4"   },
  { n = 6,   label = "d6"   },
  { n = 8,   label = "d8"   },
  { n = 10,  label = "d10"  },
  { n = 12,  label = "d12"  },
  { n = 20,  label = "d20"  },
  { n = 100, label = "d100" },
}

-- ── Layout ────────────────────────────────────────────────
local HUD_H        = 12
local DIE_LABEL_Y  = HUD_H + 6
local RESULT_SIZE  = (H >= 200) and 7 or 5
local RESULT_Y     = DIE_LABEL_Y + 22
local HISTORY_Y    = math.min(H - 26, RESULT_Y + RESULT_SIZE * 8 + 6)
local HINT_Y       = H - 12

-- ── State ─────────────────────────────────────────────────
local die_idx   = 1
local last_roll = nil   -- nil = not rolled yet
local history   = {}    -- {{label, value}, ...}

math.randomseed(uni.millis())

-- ── Helpers (pre-allocated) ───────────────────────────────
local function curDie()
  return DICE[die_idx]
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Dice Roller")
  local rolls = string.format("%d rolled", #history)
  lcd.textColor(C_DIM, C_HUD_BG)
  local rw = lcd.textWidth(rolls)
  lcd.print(W - rw - 2, 2, rolls)
end

local function drawDieLabel()
  lcd.rect(0, DIE_LABEL_Y, W, 18, C_BG)
  lcd.textSize(2)
  lcd.textColor(C_DIE, C_BG)
  local s = curDie().label
  local w = lcd.textWidth(s)
  lcd.print(math.floor((W - w) / 2), DIE_LABEL_Y, s)
  lcd.textSize(1)
end

local function drawResult(value, color)
  lcd.rect(0, RESULT_Y, W, RESULT_SIZE * 8 + 2, C_BG)
  if value == nil then
    lcd.textSize(1)
    lcd.textColor(C_DIM, C_BG)
    local s = "press OK to roll"
    local w = lcd.textWidth(s)
    lcd.print(math.floor((W - w) / 2), RESULT_Y + math.floor(RESULT_SIZE * 4), s)
  else
    lcd.textSize(RESULT_SIZE)
    lcd.textColor(color or C_RESULT, C_BG)
    local s = tostring(value)
    local w = lcd.textWidth(s)
    lcd.print(math.floor((W - w) / 2), RESULT_Y, s)
    lcd.textSize(1)
  end
end

local function drawHistory()
  lcd.rect(0, HISTORY_Y, W, 12, C_BG)
  if #history == 0 then return end
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local parts = {}
  for i = #history, math.max(1, #history - 5), -1 do
    parts[#parts + 1] = string.format("%s:%d", history[i].label, history[i].value)
  end
  local s = table.concat(parts, "  ")
  while #parts > 1 and lcd.textWidth(s) > W - 4 do
    table.remove(parts)
    s = table.concat(parts, "  ")
  end
  local w = lcd.textWidth(s)
  lcd.print(math.floor((W - w) / 2), HISTORY_Y, s)
end

local function drawHints()
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.rect(0, HINT_Y, W, 10, C_BG)
  local s = "UP/DOWN: die   OK: roll   BACK: exit"
  if lcd.textWidth(s) > W then s = "UP/DOWN die  OK roll" end
  local w = lcd.textWidth(s)
  lcd.print(math.floor((W - w) / 2), HINT_Y, s)
end

-- Rolling animation: rapid changing values, then settle. Returns the
-- final number, or nil if the user pressed BACK mid-animation.
local function rollDie()
  local die = curDie()
  for i = 1, 8 do
    if nav.btn() == "back" then return nil end
    local r = math.random(1, die.n)
    drawResult(r, C_RESULT_DIM)
    uni.beep(700 + i * 60, 18)
    uni.delay(55)
  end
  local final = math.random(1, die.n)
  drawResult(final, C_RESULT)
  uni.beep(1300, 80)
  return final
end

-- ── Init ──────────────────────────────────────────────────
lcd.fillScreen(C_BG)
drawHUD()
drawDieLabel()
drawResult(nil)
drawHistory()
drawHints()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if btn == "up" then
    die_idx = die_idx - 1
    if die_idx < 1 then die_idx = #DICE end
    drawDieLabel()
    uni.beep(900, 18)
  elseif btn == "down" then
    die_idx = die_idx + 1
    if die_idx > #DICE then die_idx = 1 end
    drawDieLabel()
    uni.beep(600, 18)
  elseif btn == "ok" then
    local r = rollDie()
    if r == nil then break end
    last_roll = r
    history[#history + 1] = { label = curDie().label, value = r }
    if #history > 16 then table.remove(history, 1) end
    drawHistory()
    drawHUD()
  end

  uni.delay(33)
end
