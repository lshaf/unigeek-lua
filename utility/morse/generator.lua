-- generator.lua — Morse Code Generator
-- Enter text via on-screen keyboard, transmit it as morse code with
-- a flashing "lamp" and matching audio. OK = send again, BACK = exit.

local lcd    = require("uni.lcd")
local nav    = require("uni.nav")
local input  = require("uni.input")
local notify = require("uni.notify")

local W, H = lcd.w(), lcd.h()

local C_BG    = lcd.color( 10,  10,  30)
local C_FG    = lcd.color(230, 230, 240)
local C_DIM   = lcd.color(120, 120, 160)
local C_ON    = lcd.color(255, 200,  60)
local C_OFF   = lcd.color( 40,  40,  60)
local C_HINT  = lcd.color(160, 160, 200)
local C_OK    = lcd.color(  0, 220, 120)

local DOT_MS    = 100
local DASH_MS   = DOT_MS * 3
local GAP_MS    = DOT_MS
local LETTER_MS = DOT_MS * 3
local WORD_MS   = DOT_MS * 7
local FREQ      = 750

local MORSE = {
  A=".-",   B="-...", C="-.-.", D="-..",  E=".",
  F="..-.", G="--.",  H="....", I="..",   J=".---",
  K="-.-",  L=".-..", M="--",   N="-.",   O="---",
  P=".--.", Q="--.-", R=".-.",  S="...",  T="-",
  U="..-",  V="...-", W=".--",  X="-..-", Y="-.--", Z="--..",
  ["0"]="-----", ["1"]=".----", ["2"]="..---", ["3"]="...--",
  ["4"]="....-", ["5"]=".....", ["6"]="-....", ["7"]="--...",
  ["8"]="---..", ["9"]="----.",
  ["."]=".-.-.-", [","]="--..--", ["?"]="..--..",
  ["!"]="-.-.--", ["/"]="-..-.",  ["@"]=".--.-.",
  ["'"]=".----.", ['"']=".-..-.", ["("]="-.--.",
  [")"]="-.--.-", [":"]="---...", [";"]="-.-.-.",
  ["="]="-...-",  ["+"]=".-.-.",  ["-"]="-....-",
  ["_"]="..--.-",
}

local LAMP_CX = math.floor(W / 2)
local LAMP_CY = math.floor(H * 0.55)
local LAMP_R  = math.max(8, math.floor(H / 8))

-- Pre-allocate functions before the loop (no closures in hot paths).
local function drawLamp(on)
  lcd.fillCircle(LAMP_CX, LAMP_CY, LAMP_R, on and C_ON or C_OFF)
  lcd.circle(LAMP_CX, LAMP_CY, LAMP_R + 2, C_DIM)
end

local function encodeForDisplay(text)
  local parts = {}
  for i = 1, #text do
    local c = string.upper(string.sub(text, i, i))
    if c == " " then
      parts[#parts + 1] = "/"
    else
      local m = MORSE[c]
      if m then parts[#parts + 1] = m end
    end
  end
  return table.concat(parts, " ")
end

local function fitText(s, maxW)
  if lcd.textWidth(s) <= maxW then return s end
  local ell = "..."
  local r = s
  while #r > 0 and lcd.textWidth(r .. ell) > maxW do
    r = string.sub(r, 1, #r - 1)
  end
  return r .. ell
end

local function drawScreen(text, morseStr, status)
  lcd.fillScreen(C_BG)
  lcd.textSize(1)
  lcd.textDatum(0)

  lcd.textColor(C_FG, C_BG)
  lcd.print(0, 0, "Morse Generator")

  lcd.textColor(C_DIM, C_BG)
  lcd.print(0, 14, fitText("TX: " .. text, W - 4))

  lcd.textColor(C_FG, C_BG)
  lcd.print(0, 28, fitText(morseStr, W - 4))

  drawLamp(false)

  if status == "playing" then
    lcd.textColor(C_HINT, C_BG)
    lcd.print(0, H - 12, "Sending... BACK to cancel")
  else
    lcd.textColor(C_OK, C_BG)
    lcd.print(0, H - 12, "Done. OK=again BACK=exit")
  end
end

local function playText(text)
  for i = 1, #text do
    if nav.btn() == "back" then return "back" end
    local c = string.upper(string.sub(text, i, i))
    if c == " " then
      uni.delay(WORD_MS - LETTER_MS)
    else
      local m = MORSE[c]
      if m then
        for j = 1, #m do
          if nav.btn() == "back" then return "back" end
          local s = string.sub(m, j, j)
          local on_ms = (s == ".") and DOT_MS or DASH_MS
          drawLamp(true)
          uni.beep(FREQ, on_ms)
          uni.delay(on_ms)
          drawLamp(false)
          uni.delay(GAP_MS)
        end
        uni.delay(LETTER_MS - GAP_MS)
      end
    end
  end
  return "done"
end

-- Main
while true do
  local text = input.text("Text to send", "SOS")
  if not text or text == "" then break end

  local morseStr = encodeForDisplay(text)
  drawScreen(text, morseStr, "playing")

  local r = playText(text)
  if r == "back" then
    notify.show("Cancelled", 600)
    break
  end

  drawScreen(text, morseStr, "done")

  local exit_loop = false
  while true do
    local b = nav.btn()
    if b == "back" then exit_loop = true; break end
    if b == "ok" then break end
    uni.delay(50)
  end
  if exit_loop then break end
end
