--[[
@title Metronome
@description Steady 4/4 metronome with an accented downbeat and adjustable tempo.
@category Utility
@author lshaf
]]
-- metronome.lua — Tempo metronome
-- A steady 4/4 click with an accented downbeat. The tempo is timed off
-- uni.millis() (not delay-accumulation) so it stays accurate even while the
-- screen redraws. A filled dot pulses on every beat; the four beat boxes
-- light up in turn with the downbeat in a brighter colour.
--
--   UP    : tempo +5 BPM   (40..240)
--   DOWN  : tempo -5 BPM
--   OK    : start / stop
--   BACK  : exit
--
-- In-memory only — there is nothing to save.

local lcd = require("uni.lcd")
local nav = require("uni.nav")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG      = lcd.color(  8,  10,  26)
local C_HUD_BG  = lcd.color( 22,  22,  38)
local C_HUD_LN  = lcd.color( 60,  60,  90)
local C_TEXT    = lcd.color(220, 220, 240)
local C_DIM     = lcd.color(140, 140, 180)
local C_HI      = lcd.color(255, 200,  60)
local C_BEAT    = lcd.color(120, 200, 255)   -- normal beat
local C_DOWN    = lcd.color(255, 150,  90)   -- accented downbeat (beat 1)
local C_OFF     = lcd.color( 40,  44,  70)   -- idle beat box / dim dot
local C_RUN     = lcd.color(120, 220, 130)
local C_STOP    = lcd.color(255, 110, 110)

-- ── Tuning ────────────────────────────────────────────────
local BPM_MIN, BPM_MAX, BPM_STEP = 40, 240, 5
local BEATS = 4                        -- 4/4 time
local FLASH_MS = 70                    -- how long the dot stays lit per beat

-- ── Layout ────────────────────────────────────────────────
local HUD_H  = 12
local HINT_Y = H - 12

local DOT_CY = math.floor(H * 0.42)
local DOT_R  = math.max(14, math.floor(math.min(W, H) * 0.16))

local BOX     = math.max(10, math.floor(W * 0.07))
local BOX_GAP = math.max(4, math.floor(BOX * 0.4))
local BOXES_W = BEATS * BOX + (BEATS - 1) * BOX_GAP
local BOX_X0  = math.floor((W - BOXES_W) / 2)
local BOX_Y   = math.min(H - 30, DOT_CY + DOT_R + 14)

local BPM_Y = HUD_H + 6

-- ── State (declared once) ─────────────────────────────────
local bpm        = 120
local running    = false
local beat       = 0          -- 0 = nothing lit yet; 1..BEATS while running
local next_beat  = 0          -- millis() timestamp of the next click
local flash_off  = 0          -- millis() after which the dot reverts to dim
local dot_lit    = false      -- is the dot currently drawn bright?

-- shown-state sentinels so we only redraw what changed
local shown_bpm  = -1
local shown_run  = nil
local shown_beat = -1
local shown_dot  = nil        -- colour the dot was last painted with

-- ── Pre-allocated helpers ─────────────────────────────────
local function interval()
  return 60000 / bpm           -- ms between beats (float is fine for timing)
end

local function boxX(i)
  return BOX_X0 + (i - 1) * (BOX + BOX_GAP)
end

local function drawDot(col)
  lcd.fillCircle(math.floor(W / 2), DOT_CY, DOT_R, col)
end

local function drawBpm()
  lcd.textSize(3)
  lcd.textColor(C_HI, C_BG)
  local s  = string.format("%3d", bpm)
  local sw = lcd.textWidth(s)
  lcd.print(math.floor((W - sw) / 2), BPM_Y, s)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local lbl = "BPM"
  lcd.print(math.floor((W - lcd.textWidth(lbl)) / 2), BPM_Y + 26, lbl)
  shown_bpm = bpm
end

local function drawBoxes()
  for i = 1, BEATS do
    local col = C_OFF
    if running and i == beat then col = (i == 1) and C_DOWN or C_BEAT end
    lcd.rect(boxX(i), BOX_Y, BOX, BOX, col)
  end
  shown_beat = running and beat or 0
end

local function drawState()
  lcd.rect(0, HINT_Y, W, 10, C_BG)
  lcd.textSize(1)
  if running then
    lcd.textColor(C_RUN, C_BG)
    local s = "RUNNING   OK stop   BACK exit"
    lcd.print(math.floor((W - lcd.textWidth(s)) / 2), HINT_Y, s)
  else
    lcd.textColor(C_DIM, C_BG)
    local s = "UP/DOWN tempo   OK start   BACK exit"
    lcd.print(math.floor((W - lcd.textWidth(s)) / 2), HINT_Y, s)
  end
  shown_run = running
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_HUD_LN)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Metronome")
  lcd.textColor(C_DIM, C_HUD_BG)
  local s = string.format("%d/4", BEATS)
  lcd.print(W - lcd.textWidth(s) - 2, 2, s)
end

-- ── Init: static background drawn once ────────────────────
lcd.fillScreen(C_BG)
drawHUD()
drawDot(C_OFF)
drawBpm()
drawBoxes()
drawState()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if btn == "up" or btn == "down" then
    local d = (btn == "up") and BPM_STEP or -BPM_STEP
    local nb = bpm + d
    if nb < BPM_MIN then nb = BPM_MIN end
    if nb > BPM_MAX then nb = BPM_MAX end
    if nb ~= bpm then
      bpm = nb
      -- reschedule from now so the tempo change takes effect cleanly
      if running then next_beat = uni.millis() + interval() end
    end
  elseif btn == "ok" then
    running = not running
    if running then
      beat       = 0
      next_beat  = uni.millis()        -- fire the first beat immediately
    else
      beat       = 0
      dot_lit    = false
    end
  end

  -- Beat scheduling (only while running)
  if running then
    local now = uni.millis()
    if now >= next_beat then
      beat = beat + 1
      if beat > BEATS then beat = 1 end
      if beat == 1 then uni.beep(1760, 22) else uni.beep(1245, 16) end
      dot_lit   = true
      flash_off = now + FLASH_MS
      next_beat = next_beat + interval()
      -- if we fell badly behind (slow frame), resync rather than machine-gun
      if now - next_beat > interval() then next_beat = now + interval() end
    end
    if dot_lit and now >= flash_off then dot_lit = false end
  end

  -- ── Redraw only what changed ──
  if bpm ~= shown_bpm then drawBpm() end
  if running ~= shown_run then drawState() end

  -- dot: bright while lit (downbeat tinted), dim otherwise
  local want_dot = (running and dot_lit)
                   and ((beat == 1) and C_DOWN or C_BEAT)
                   or  C_OFF
  if want_dot ~= shown_dot then
    drawDot(want_dot)
    shown_dot = want_dot
  end

  if (running and beat or 0) ~= shown_beat then drawBoxes() end

  uni.delay(8)
end
