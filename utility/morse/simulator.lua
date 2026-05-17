-- simulator.lua — Morse Code Simulator
-- Tap out morse with the buttons; press OK to look the pattern up.
--
--   UP   : add a dot (.)
--   DOWN : add a dash (-)
--   OK   : look up the current buffer
--   BACK : exit
--
-- A valid pattern shows the letter big in the centre and appends to the
-- scrolling history. An unknown pattern shows "?" plus the failed code
-- on the line below; the next UP / DOWN clears the error and starts a
-- fresh entry. The buffer caps at MAX_MORSE_LEN symbols — extra presses
-- past the cap just beep without changing the buffer.

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

local MAX_HISTORY   = 18
local MAX_MORSE_LEN = 6

-- ── Layout ───────────────────────────────────────────────
local TITLE_Y       = 0
local HISTORY_Y     = 14
local BUILDING_Y    = 30
local LETTER_SIZE   = (H >= 200) and 5 or 4
local LETTER_Y      = math.floor(H * 0.42)
local LETTER_BAND_H = LETTER_SIZE * 10
local ERROR_Y       = LETTER_Y + LETTER_BAND_H + 2
local HINT1_Y       = H - 22
local HINT2_Y       = H - 12

-- ── State (declared once) ────────────────────────────────
local history       = ""
local current_morse = ""
local last_letter   = ""
local last_error    = ""

local last_history_shown = "\0"
local last_morse_shown   = "\0"
local last_letter_shown  = "\0"
local last_error_shown   = "\0"

-- ── Helpers (pre-allocated) ──────────────────────────────
local function drawTitle()
  lcd.textSize(1)
  lcd.textColor(C_FG, C_BG)
  lcd.print(0, TITLE_Y, "Morse Simulator")
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
    local s = "(UP = .   DOWN = -)"
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

local function drawError()
  lcd.rect(0, ERROR_Y, W, 10, C_BG)
  if last_error == "" then return end
  lcd.textSize(1)
  lcd.textColor(C_BAD, C_BG)
  local s = "no match: " .. last_error
  local w = lcd.textWidth(s)
  lcd.print(math.floor((W - w) / 2), ERROR_Y, s)
end

local function drawHints()
  lcd.textSize(1)
  lcd.textColor(C_HINT, C_BG)
  lcd.print(0, HINT1_Y, "UP = dot    DOWN = dash")
  lcd.print(0, HINT2_Y, "OK = lookup    BACK = exit")
end

local function recordSymbol(sym)
  if #current_morse >= MAX_MORSE_LEN then
    uni.beep(150, 120)
    return
  end
  -- A new dot/dash dismisses the previous error state.
  if last_error ~= "" then
    last_error  = ""
    last_letter = ""
  end
  current_morse = current_morse .. sym
  if sym == "." then
    uni.beep(950, 50)
  else
    uni.beep(550, 150)
  end
end

local function commitBuffer()
  if current_morse == "" then return end
  local letter = LOOKUP[current_morse]
  if letter then
    last_letter = letter
    history     = history .. letter
    if #history > MAX_HISTORY then
      history = string.sub(history, -MAX_HISTORY)
    end
    last_error = ""
    uni.beep(1400, 30)
  else
    last_letter = "?"
    last_error  = current_morse
    uni.beep(400, 80)
    uni.delay(100)
    uni.beep(200, 150)
  end
  current_morse = ""
end

-- ── Init ─────────────────────────────────────────────────
lcd.fillScreen(C_BG)
drawTitle()
drawHistory();   last_history_shown = history
drawBuilding();  last_morse_shown   = current_morse
drawLetter();    last_letter_shown  = last_letter
drawError();     last_error_shown   = last_error
drawHints()

-- ── Main loop ────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if btn == "up" then
    recordSymbol(".")
  elseif btn == "down" then
    recordSymbol("-")
  elseif btn == "ok" then
    commitBuffer()
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
  if last_error ~= last_error_shown then
    drawError()
    last_error_shown = last_error
  end

  uni.delay(25)
end
