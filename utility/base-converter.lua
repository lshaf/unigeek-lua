-- base-converter.lua — Base Converter
-- Enter a decimal value (0..65535); see it expressed in hex, octal,
-- and binary simultaneously. Binary is space-grouped every 4 bits.
--
--   OK   : another conversion
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
local C_DEC    = lcd.color(120, 220, 180)
local C_HEX    = lcd.color(255, 200,  80)
local C_OCT    = lcd.color(220, 130, 220)
local C_BIN    = lcd.color(160, 200, 255)

local HUD_H   = 12
local MAX_VAL = 65535

local function toBin(n)
  if n == 0 then return "0" end
  local bits = {}
  while n > 0 do
    bits[#bits + 1] = tostring(n % 2)
    n = math.floor(n / 2)
  end
  -- reverse
  local rev = {}
  for i = #bits, 1, -1 do rev[#rev + 1] = bits[i] end
  return table.concat(rev)
end

local function groupBin(s)
  local pad = (4 - (#s % 4)) % 4
  s = string.rep("0", pad) .. s
  local parts = {}
  for i = 1, #s, 4 do parts[#parts + 1] = string.sub(s, i, i + 3) end
  return table.concat(parts, " ")
end

local function toOct(n)
  if n == 0 then return "0" end
  local digits = {}
  while n > 0 do
    digits[#digits + 1] = tostring(n % 8)
    n = math.floor(n / 8)
  end
  local rev = {}
  for i = #digits, 1, -1 do rev[#rev + 1] = digits[i] end
  return table.concat(rev)
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Base Converter")
end

local function drawRow(y, label, color, value)
  lcd.textSize(1)
  lcd.textColor(C_LABEL, C_BG)
  lcd.print(2, y, label)
  lcd.textColor(color, C_BG)
  lcd.print(40, y, value)
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
  local n = input.number(string.format("Decimal (0..%d)", MAX_VAL), 0, MAX_VAL, 0)
  if n == nil then break end

  lcd.fillScreen(C_BG)
  drawHUD()

  local y = HUD_H + 14
  drawRow(y,      "DEC", C_DEC, tostring(n))
  drawRow(y + 16, "HEX", C_HEX, string.format("0x%X", n))
  drawRow(y + 32, "OCT", C_OCT, "0"  .. toOct(n))
  drawRow(y + 48, "BIN", C_BIN, groupBin(toBin(n)))

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
