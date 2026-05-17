-- simulator.lua — Morse Code Simulator
-- The user taps out morse; after a short idle the buffer decodes to a letter.
--
--   Touch:         short tap = dot   long hold = dash
--   UP   button:   dot
--   DOWN button:   dash
--   OK   button:   commit the current buffer immediately (skip the idle wait)
--   BACK button:   exit
--
-- After LETTER_TIMEOUT_MS of no input, whatever is in the buffer is decoded.
-- Unknown patterns decode to `?`. Decoded letters accumulate in a scrolling
-- history line at the top; the most recent letter is shown big in the centre.

local lcd = require("uni.lcd")
local nav = require("uni.nav")

local W, H = lcd.w(), lcd.h()

-- ── Colours ──────────────────────────────────────────────
local C_BG    = lcd.color( 10,  10,  30)
local C_FG    = lcd.color(230, 230, 240)
local C_DIM   = lcd.color(110, 110, 150)
local C_HINT  = lcd.color(160, 160, 200)
local C_LET   = lcd.color( 80, 200, 255)
local C_DOT   = lcd.color(255, 220,  60)
local C_DASH  = lcd.color( 80, 220, 120)
local C_ON    = lcd.color(255, 200,  60)
local C_OFF   = lcd.color( 40,  40,  60)
local C_BAD   = lcd.color(255, 110, 110)

-- ── Morse table + reverse lookup ─────────────────────────
local MORSE = {
  A=".-",   B="-...", C="-.-.", D="-..",  E=".",
  F="..-.", G="--.",  H="....", I="..",   J=".---",
  K="-.-",  L=".-..", M="--",   N="-.",   O="---",
  P=".--.", Q="--.-", R=".-.",  S="...",  T="-",
  U="..-",  V="...-", W=".--",  X="-..-", Y="-.--", Z="--..",
  ["0"]="-----", ["1"]=".----", ["2"]="..---", ["3"]="...--",
  ["4"]="....-", ["5"]=".....", ["6"]="-....", ["7"]="--...",
  ["8"]="---..", ["9"]="----.",
}
local LOOKUP = {}
for letter, code in pairs(MORSE) do LOOKUP[code] = letter end

-- ── Timing / sizing ──────────────────────────────────────
local DASH_THRESHOLD_MS = 200    -- touch held this long counts as a dash
local LETTER_TIMEOUT_MS = 1100   -- idle after which the buffer decodes
local MAX_HISTORY       = 18
local MAX_MORSE_LEN     = 6

-- ── Layout ───────────────────────────────────────────────
local TITLE_Y     = 0
local INDICATOR_X = W - 8
local INDICATOR_Y = 4
local INDICATOR_R = 3
local HISTORY_Y   = 14
local BUILDING_Y  = 30
local LETTER_SIZE = (H >= 200) and 5 or 4
local LETTER_Y    = math.floor(H * 0.45)
local LETTER_BAND_H = LETTER_SIZE * 10
local HINT1_Y     = H - 22
local HINT2_Y     = H - 12

-- ── State (declared once) ────────────────────────────────
local history             = ""
local current_morse       = ""
local last_input_time     = 0
local last_letter         = ""
local was_touched         = false
local touch_start         = nil
local last_history_shown  = "\0"
local last_morse_shown    = "\0"
local last_letter_shown   = "\0"
local last_indicator      = false

-- ── Helpers (pre-allocated) ──────────────────────────────
local function drawTitle()
  lcd.textSize(1)
  lcd.textColor(C_FG, C_BG)
  lcd.print(0, TITLE_Y, "Morse Simulator")
end

local function drawIndicator(on)
  lcd.fillCircle(INDICATOR_X, INDICATOR_Y, INDICATOR_R, on and C_ON or C_OFF)
end

local function fitTextLeft(s, maxW)
  if lcd.textWidth(s) <= maxW then return s end
  local r = s
  while #r > 0 and lcd.textWidth("..." .. r) > maxW do
    r = string.sub(r, 2)
  end
  return "..." .. r
end

local function drawHistory()
  lcd.textSize(1)
  lcd.rect(0, HISTORY_Y, W, 10, C_BG)
  lcd.textColor(C_DIM, C_BG)
  local label = "Decoded: "
  lcd.print(0, HISTORY_Y, label)
  local labelW = lcd.textWidth(label)
  lcd.textColor(C_FG, C_BG)
  local shown = fitTextLeft(history, W - labelW - 2)
  lcd.print(labelW, HISTORY_Y, shown)
end

local function drawBuilding()
  lcd.rect(0, BUILDING_Y, W, 20, C_BG)
  if current_morse == "" then
    lcd.textSize(1)
    lcd.textColor(C_DIM, C_BG)
    local s = "(tap dot / hold dash)"
    local w = lcd.textWidth(s)
    lcd.print(math.floor((W - w) / 2), BUILDING_Y + 4, s)
  else
    lcd.textSize(2)
    lcd.textColor(C_DOT, C_BG)
    local w = lcd.textWidth(current_morse)
    lcd.print(math.floor((W - w) / 2), BUILDING_Y, current_morse)
    lcd.textSize(1)
  end
end

local function drawLetter()
  lcd.rect(0, LETTER_Y, W, LETTER_BAND_H, C_BG)
  if last_letter == "" then return end
  lcd.textSize(LETTER_SIZE)
  if last_letter == "?" then
    lcd.textColor(C_BAD, C_BG)
  else
    lcd.textColor(C_LET, C_BG)
  end
  local w = lcd.textWidth(last_letter)
  lcd.print(math.floor((W - w) / 2), LETTER_Y, last_letter)
  lcd.textSize(1)
end

local function drawHints()
  lcd.textSize(1)
  lcd.textColor(C_HINT, C_BG)
  lcd.print(0, HINT1_Y, "tap=dot  hold=dash  UP=.  DOWN=-")
  lcd.print(0, HINT2_Y, "OK=commit now      BACK=exit")
end

local function recordSymbol(sym)
  if #current_morse >= MAX_MORSE_LEN then return end
  current_morse = current_morse .. sym
  last_input_time = uni.millis()
  if sym == "." then
    uni.beep(950, 50)
  else
    uni.beep(550, 150)
  end
end

local function commitBuffer()
  if current_morse == "" then return end
  local letter = LOOKUP[current_morse] or "?"
  last_letter = letter
  if letter ~= "?" then
    history = history .. letter
    if #history > MAX_HISTORY then
      history = string.sub(history, -MAX_HISTORY)
    end
    uni.beep(1400, 30)
  else
    uni.beep(200, 200)
  end
  current_morse = ""
end

-- ── Init ─────────────────────────────────────────────────
lcd.fillScreen(C_BG)
drawTitle()
drawIndicator(false)
drawHistory();   last_history_shown = history
drawBuilding();  last_morse_shown   = current_morse
drawLetter();    last_letter_shown  = last_letter
drawHints()

last_input_time = uni.millis()

-- ── Main loop ────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  local now         = uni.millis()
  local touched_now = nav.isTouched()

  -- Touch hold detection — start on press, decide on release.
  if touched_now and not was_touched then
    touch_start = now
  elseif (not touched_now) and was_touched and touch_start ~= nil then
    local duration = now - touch_start
    local sym = (duration >= DASH_THRESHOLD_MS) and "-" or "."
    recordSymbol(sym)
    touch_start = nil
  end
  was_touched = touched_now

  -- Button input
  if btn == "up" then
    recordSymbol(".")
  elseif btn == "down" then
    recordSymbol("-")
  elseif btn == "ok" then
    commitBuffer()
  end

  -- Auto-commit after idle
  if current_morse ~= "" and (now - last_input_time) >= LETTER_TIMEOUT_MS then
    commitBuffer()
  end

  -- Diff-render
  if touched_now ~= last_indicator then
    drawIndicator(touched_now)
    last_indicator = touched_now
  end
  if current_morse ~= last_morse_shown then
    drawBuilding()
    last_morse_shown = current_morse
  end
  if history ~= last_history_shown then
    drawHistory()
    last_history_shown = history
  end
  if last_letter ~= last_letter_shown then
    drawLetter()
    last_letter_shown = last_letter
  end

  uni.delay(25)
end
