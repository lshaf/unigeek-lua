-- caesar-cipher.lua — Caesar Cipher
-- Enter text and a shift amount; the script encodes the text by shifting
-- each letter that many positions in the alphabet. Negative shifts
-- decode. Non-letters pass through unchanged.
--
--   OK   : do another
--   BACK : exit

local lcd   = require("uni.lcd")
local nav   = require("uni.nav")
local input = require("uni.input")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG     = lcd.color( 10,  12,  28)
local C_HUD_BG = lcd.color( 22,  22,  38)
local C_TEXT   = lcd.color(220, 220, 240)
local C_DIM    = lcd.color(140, 140, 180)
local C_LABEL  = lcd.color(180, 180, 220)
local C_IN     = lcd.color(255, 200,  80)
local C_OUT    = lcd.color(120, 220, 180)

local HUD_H = 12

local function caesar(text, shift)
  shift = shift % 26
  local out = {}
  for i = 1, #text do
    local c = string.byte(text, i)
    if c >= 65 and c <= 90 then
      out[i] = string.char((c - 65 + shift) % 26 + 65)
    elseif c >= 97 and c <= 122 then
      out[i] = string.char((c - 97 + shift) % 26 + 97)
    else
      out[i] = string.char(c)
    end
  end
  return table.concat(out)
end

local function wrapText(s, maxW, maxLines)
  local lines = { "" }
  for word in string.gmatch(s, "%S+") do
    local trial = (lines[#lines] == "") and word or (lines[#lines] .. " " .. word)
    if lcd.textWidth(trial) <= maxW then
      lines[#lines] = trial
    else
      if #lines >= maxLines then
        lines[#lines] = lines[#lines] .. "..."
        return lines
      end
      lines[#lines + 1] = word
    end
  end
  return lines
end

local function drawHUD(label)
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Caesar Cipher")
  if label then
    lcd.textColor(C_DIM, C_HUD_BG)
    local sw = lcd.textWidth(label)
    lcd.print(W - sw - 2, 2, label)
  end
end

local function drawBlock(y, label, color, lines)
  lcd.textSize(1)
  lcd.textColor(C_LABEL, C_BG)
  lcd.print(2, y, label)
  lcd.textColor(color, C_BG)
  for i = 1, #lines do
    lcd.print(2, y + 12 + (i - 1) * 10, lines[i])
  end
end

local function drawHint(text)
  lcd.rect(0, H - 12, W, 12, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local sw = lcd.textWidth(text)
  lcd.print(math.floor((W - sw) / 2), H - 12, text)
end

-- ── Main loop ─────────────────────────────────────────────
while true do
  local text = input.text("Text", "Hello World")
  if text == nil or text == "" then break end

  local shift = input.number("Shift (negative = decode)", -25, 25, 3)
  if shift == nil then break end

  local result = caesar(text, shift)

  lcd.fillScreen(C_BG)
  drawHUD(string.format("shift %+d", shift))

  local INPUT_Y  = HUD_H + 8
  local OUTPUT_Y = math.floor(H * 0.5)
  local MAX_W    = W - 4

  drawBlock(INPUT_Y,  "INPUT",  C_IN,  wrapText(text,   MAX_W, 3))
  drawBlock(OUTPUT_Y, "OUTPUT", C_OUT, wrapText(result, MAX_W, 3))
  drawHint("OK = another   BACK = exit")

  local exit_loop = false
  while true do
    local btn = nav.btn()
    if btn == "back" then exit_loop = true; break end
    if btn == "ok"   then break end
    uni.delay(50)
  end
  if exit_loop then break end
end
