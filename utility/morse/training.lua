-- training.lua — Morse Code Trainer / Reference
-- Browse the morse alphabet one letter at a time. Each entry plays
-- the audio with a synced "lamp" and highlighted dot/dash strip.
--   UP   / LEFT  = previous
--   DOWN / RIGHT = next
--   OK           = replay current letter
--   BACK         = exit

local lcd = require("uni.lcd")
local nav = require("uni.nav")

local W, H = lcd.w(), lcd.h()

local C_BG    = lcd.color( 10,  10,  30)
local C_FG    = lcd.color(230, 230, 240)
local C_DIM   = lcd.color(110, 110, 150)
local C_HINT  = lcd.color(160, 160, 200)
local C_ON    = lcd.color(255, 200,  60)
local C_OFF   = lcd.color( 40,  40,  60)
local C_LET   = lcd.color( 80, 200, 255)
local C_DOT   = lcd.color(255, 220,  60)
local C_DASH  = lcd.color( 80, 220, 120)

local DOT_MS  = 120
local DASH_MS = DOT_MS * 3
local GAP_MS  = DOT_MS
local FREQ    = 750

local TABLE_ = {
  {"A",".-"},   {"B","-..."}, {"C","-.-."}, {"D","-.."},
  {"E","."},    {"F","..-."}, {"G","--."},  {"H","...."},
  {"I",".."},   {"J",".---"}, {"K","-.-"},  {"L",".-.."},
  {"M","--"},   {"N","-."},   {"O","---"},  {"P",".--."},
  {"Q","--.-"}, {"R",".-."},  {"S","..."},  {"T","-"},
  {"U","..-"},  {"V","...-"}, {"W",".--"},  {"X","-..-"},
  {"Y","-.--"}, {"Z","--.."},
  {"0","-----"},{"1",".----"},{"2","..---"},{"3","...--"},
  {"4","....-"},{"5","....."},{"6","-...."},{"7","--..."},
  {"8","---.."},{"9","----."},
}
local N = #TABLE_

local LETTER_SIZE = (H >= 200) and 4 or 3

local LAMP_CX = math.floor(W / 2)
local LAMP_CY = math.floor(H * 0.55)
local LAMP_R  = math.max(8, math.floor(H / 12))

local STRIP_Y = math.floor(H * 0.72)
local SYM_W   = 14
local SYM_H   = 14

local MORSE_Y = math.floor(H * 0.86)
local HINT_Y  = H - 12

-- Pre-allocate all helpers before the main loop.
local function drawLamp(on)
  lcd.fillCircle(LAMP_CX, LAMP_CY, LAMP_R, on and C_ON or C_OFF)
  lcd.circle(LAMP_CX, LAMP_CY, LAMP_R + 2, C_DIM)
end

local function drawSymbols(code, hl)
  local total = #code * SYM_W
  local x0 = math.floor((W - total) / 2)
  lcd.rect(0, STRIP_Y - 2, W, SYM_H + 4, C_BG)
  for i = 1, #code do
    local s = string.sub(code, i, i)
    local x = x0 + (i - 1) * SYM_W
    if s == "." then
      local c = (i == hl) and C_DOT or C_DIM
      lcd.fillCircle(x + math.floor(SYM_W / 2), STRIP_Y + math.floor(SYM_H / 2), 4, c)
    else
      local c = (i == hl) and C_DASH or C_DIM
      lcd.rect(x + 1, STRIP_Y + math.floor(SYM_H / 2) - 3, SYM_W - 2, 6, c)
    end
  end
end

local function drawScreen(idx, ch, code)
  lcd.fillScreen(C_BG)
  lcd.textSize(1)
  lcd.textDatum(0)

  lcd.textColor(C_FG, C_BG)
  lcd.print(0, 0, "Morse Trainer")

  local idxStr = string.format("%02d/%02d", idx, N)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(W - lcd.textWidth(idxStr) - 2, 0, idxStr)

  lcd.textSize(LETTER_SIZE)
  lcd.textColor(C_LET, C_BG)
  local lw = lcd.textWidth(ch)
  lcd.print(math.floor((W - lw) / 2), 18, ch)
  lcd.textSize(1)

  drawLamp(false)
  drawSymbols(code, 0)

  lcd.textColor(C_FG, C_BG)
  local mw = lcd.textWidth(code)
  lcd.print(math.floor((W - mw) / 2), MORSE_Y, code)

  lcd.textColor(C_HINT, C_BG)
  lcd.print(0, HINT_Y, "<- prev   OK replay   next ->")
end

-- Play the code; abort early on any nav press and bubble it back to caller.
local function playCode(code)
  for i = 1, #code do
    local b = nav.btn()
    if b ~= "none" and b ~= "" then return b end
    local s = string.sub(code, i, i)
    local on_ms = (s == ".") and DOT_MS or DASH_MS
    drawLamp(true)
    drawSymbols(code, i)
    uni.beep(FREQ, on_ms)
    uni.delay(on_ms)
    drawLamp(false)
    drawSymbols(code, 0)
    uni.delay(GAP_MS)
  end
  return "done"
end

local idx     = 1
local pending = "ok"  -- force initial playback

while true do
  local b
  if pending then
    b = pending
    pending = nil
  else
    b = nav.btn()
  end

  if b == "back" then
    break
  elseif b == "left" or b == "up" then
    idx = idx - 1
    if idx < 1 then idx = N end
    local ch, code = TABLE_[idx][1], TABLE_[idx][2]
    drawScreen(idx, ch, code)
    local r = playCode(code)
    if r ~= "done" then pending = r end
  elseif b == "right" or b == "down" then
    idx = idx + 1
    if idx > N then idx = 1 end
    local ch, code = TABLE_[idx][1], TABLE_[idx][2]
    drawScreen(idx, ch, code)
    local r = playCode(code)
    if r ~= "done" then pending = r end
  elseif b == "ok" then
    local ch, code = TABLE_[idx][1], TABLE_[idx][2]
    drawScreen(idx, ch, code)
    local r = playCode(code)
    if r ~= "done" then pending = r end
  else
    uni.delay(40)
  end
end
