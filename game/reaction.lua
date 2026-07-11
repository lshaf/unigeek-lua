--[[
@title Reaction Timer
@description Test your reflexes — wait for the go signal, then tap as fast as you can.
@category Game
@author lshaf
]]
-- reaction.lua — Reaction Timer
-- A coloured panel guides the user through each attempt:
--   blue READY?  → press OK to start
--   yellow WAIT  → hold; do NOT press until green
--   green GO!    → press OK as fast as you can
--   teal RESULT  → shows reaction in ms (and updates best)
--   red TOO SOON → pressed during the wait — retry
--
--   OK   : start / acknowledge result / retry after a fault
--   BACK : exit
--
-- Best time persists to /unigeek/games/reaction.txt.

local lcd = require("uni.lcd")
local nav = require("uni.nav")
local sd  = require("uni.sd")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG     = lcd.color( 10,  12,  28)
local C_HUD_BG = lcd.color( 22,  22,  38)
local C_TEXT   = lcd.color(220, 220, 240)
local C_DIM    = lcd.color(140, 140, 180)
local C_HI     = lcd.color(255, 200,  60)
local C_READY  = lcd.color( 70,  90, 160)
local C_WAIT   = lcd.color(220, 160,  50)
local C_GO     = lcd.color( 50, 200,  80)
local C_EARLY  = lcd.color(220,  70,  70)
local C_RESULT = lcd.color(110, 220, 200)

local SAVE_PATH = "/unigeek/games/reaction.txt"

local HUD_H      = 12
local PANEL_TOP  = HUD_H + 1
local TITLE_SIZE = 3
local SUB_SIZE   = 1

-- ── State ─────────────────────────────────────────────────
local state            -- "ready" | "waiting" | "go" | "result" | "early"
local cue_time
local go_time
local result_ms
local best_ms

math.randomseed(uni.millis())

local function loadBest()
  if not sd.exists(SAVE_PATH) then return nil end
  return tonumber(sd.read(SAVE_PATH) or "")
end

local function saveBest(ms)
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
  sd.write(SAVE_PATH, tostring(ms))
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Reaction Timer")
  if best_ms then
    local s = string.format("BEST %d ms", best_ms)
    lcd.textColor(C_HI, C_HUD_BG)
    local w = lcd.textWidth(s)
    lcd.print(W - w - 2, 2, s)
  end
end

local function drawPanel(color, title, sub)
  lcd.rect(0, PANEL_TOP, W, H - PANEL_TOP, color)

  lcd.textSize(TITLE_SIZE)
  lcd.textColor(C_BG, color)
  local tw = lcd.textWidth(title)
  local th = TITLE_SIZE * 8
  local center_y = PANEL_TOP + math.floor((H - PANEL_TOP - th) / 2) - 6
  lcd.print(math.floor((W - tw) / 2), center_y, title)

  if sub then
    lcd.textSize(SUB_SIZE)
    lcd.textColor(C_BG, color)
    local sw = lcd.textWidth(sub)
    lcd.print(math.floor((W - sw) / 2), H - 16, sub)
  end
  lcd.textSize(1)
end

-- ── Init ──────────────────────────────────────────────────
best_ms = loadBest()
lcd.fillScreen(C_BG)
drawHUD()
state = "ready"
drawPanel(C_READY, "READY?", "press OK to start")

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if state == "ready" then
    if btn == "ok" then
      state    = "waiting"
      cue_time = uni.millis() + math.random(1500, 4500)
      drawPanel(C_WAIT, "WAIT", "press OK on green")
    end

  elseif state == "waiting" then
    if btn == "ok" then
      state = "early"
      drawPanel(C_EARLY, "TOO SOON", "press OK to retry")
      uni.beep(200, 200)
    elseif uni.millis() >= cue_time then
      go_time = uni.millis()
      state   = "go"
      drawPanel(C_GO, "GO!", "press OK now")
      uni.beep(1300, 50)
    end

  elseif state == "go" then
    if btn == "ok" then
      result_ms = uni.millis() - go_time
      state     = "result"
      local title = string.format("%d ms", result_ms)
      local sub
      if best_ms == nil or result_ms < best_ms then
        best_ms = result_ms
        saveBest(best_ms)
        sub = "NEW BEST!  OK to retry"
      else
        sub = string.format("best %d ms - OK to retry", best_ms)
      end
      drawPanel(C_RESULT, title, sub)
      drawHUD()
      uni.beep(900, 60)
    end

  elseif state == "result" or state == "early" then
    if btn == "ok" then
      state = "ready"
      drawPanel(C_READY, "READY?", "press OK to start")
    end
  end

  uni.delay(15)
end
