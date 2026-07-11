--[[
@title Stopwatch
@description MM:SS.cc stopwatch with lap recording (in-memory only).
@category Utility
@author lshaf
]]
-- stopwatch.lua — Stopwatch
-- Big MM:SS.cc display with lap recording. State is in-memory only —
-- exiting the script clears everything.
--
--   OK    : start / stop toggle
--   UP    : record a lap (while running)
--   DOWN  : reset (while stopped)
--   BACK  : exit

local lcd = require("uni.lcd")
local nav = require("uni.nav")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG       = lcd.color( 10,  12,  28)
local C_HUD_BG   = lcd.color( 22,  22,  38)
local C_TEXT     = lcd.color(220, 220, 240)
local C_DIM      = lcd.color(140, 140, 180)
local C_GREEN    = lcd.color( 80, 220, 130)
local C_YELLOW   = lcd.color(255, 200,  60)
local C_DISPLAY  = lcd.color(150, 230, 255)
local C_LAP      = lcd.color(220, 220, 240)

-- ── Layout / sizing ───────────────────────────────────────
local HUD_H      = 12
-- Pick the biggest font that lets "MM:SS.cc" (8 chars, 6px each at size 1) fit
local TIME_SIZE
if     W >= 240 then TIME_SIZE = 5
elseif W >= 192 then TIME_SIZE = 4
elseif W >= 144 then TIME_SIZE = 3
else                 TIME_SIZE = 2
end
local TIME_Y     = HUD_H + 14
local TIME_H     = TIME_SIZE * 8
local LAPS_Y     = TIME_Y + TIME_H + 10
local HINT_Y     = H - 12
local MAX_LAPS   = 5

-- ── State ─────────────────────────────────────────────────
local running    = false
local start_ms   = 0
local elapsed_ms = 0     -- carry-over from previous run segments
local laps       = {}    -- {{total=ms, split=ms}, ...}
local last_status = nil

-- ── Helpers ───────────────────────────────────────────────
local function currentMs()
  if running then return uni.millis() - start_ms + elapsed_ms end
  return elapsed_ms
end

local function fmtTime(ms)
  local cs = math.floor(ms / 10) % 100
  local s  = math.floor(ms / 1000) % 60
  local m  = math.floor(ms / 60000)
  return string.format("%02d:%02d.%02d", m, s, cs)
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Stopwatch")

  local status, sc
  if running then
    status, sc = "RUNNING", C_GREEN
  elseif elapsed_ms > 0 then
    status, sc = "STOPPED", C_YELLOW
  else
    status, sc = "READY",   C_DIM
  end
  lcd.textColor(sc, C_HUD_BG)
  local sw = lcd.textWidth(status)
  lcd.print(W - sw - 2, 2, status)
  last_status = status
end

local function drawTime(ms)
  lcd.textSize(TIME_SIZE)
  lcd.textColor(C_DISPLAY, C_BG)
  local s  = fmtTime(ms)
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), TIME_Y, s)
  lcd.textSize(1)
end

local function drawLaps()
  lcd.rect(0, LAPS_Y, W, H - LAPS_Y - 12, C_BG)
  if #laps == 0 then return end
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local hdr = string.format("LAPS (%d)", #laps)
  local hw = lcd.textWidth(hdr)
  lcd.print(math.floor((W - hw) / 2), LAPS_Y, hdr)

  local n = math.min(#laps, MAX_LAPS)
  for i = 1, n do
    local lap = laps[#laps - i + 1]
    local idx = #laps - i + 1
    local s = string.format("L%-2d  %s  +%s", idx, fmtTime(lap.total), fmtTime(lap.split))
    lcd.textColor(C_LAP, C_BG)
    local sw = lcd.textWidth(s)
    lcd.print(math.floor((W - sw) / 2), LAPS_Y + 12 + (i - 1) * 10, s)
  end
end

local function drawHints()
  lcd.rect(0, HINT_Y, W, 10, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local s
  if running then
    s = "OK stop   UP lap   BACK exit"
  elseif elapsed_ms > 0 then
    s = "OK resume   DOWN reset   BACK exit"
  else
    s = "OK start   BACK exit"
  end
  if lcd.textWidth(s) > W then s = "OK toggle  UP lap  DOWN reset" end
  if lcd.textWidth(s) > W then s = "OK / UP / DOWN" end
  local w = lcd.textWidth(s)
  lcd.print(math.floor((W - w) / 2), HINT_Y, s)
end

-- ── Init ──────────────────────────────────────────────────
lcd.fillScreen(C_BG)
drawHUD()
drawTime(0)
drawLaps()
drawHints()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if btn == "ok" then
    if running then
      elapsed_ms = uni.millis() - start_ms + elapsed_ms
      running    = false
      drawTime(elapsed_ms)
      drawHUD()
      drawHints()
      uni.beep(440, 40)
    else
      start_ms = uni.millis()
      running  = true
      drawHUD()
      drawHints()
      uni.beep(880, 40)
    end

  elseif btn == "up" then
    if running then
      local total     = currentMs()
      local prev_total = (#laps > 0) and laps[#laps].total or 0
      laps[#laps + 1] = { total = total, split = total - prev_total }
      if #laps > MAX_LAPS * 2 then table.remove(laps, 1) end
      drawLaps()
      uni.beep(1100, 30)
    end

  elseif btn == "down" then
    if (not running) and (elapsed_ms > 0 or #laps > 0) then
      elapsed_ms = 0
      laps       = {}
      drawTime(0)
      drawLaps()
      drawHUD()
      drawHints()
      uni.beep(300, 40)
    end
  end

  if running then
    drawTime(currentMs())
  end

  uni.delay(30)
end
