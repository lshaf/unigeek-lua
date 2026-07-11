--[[
@title LED Resistor
@description Calculate the series resistor for an LED from supply voltage, forward voltage, and target current.
@category Utility
@author lshaf
]]
-- led-resistor.lua — LED series-resistor calculator
-- Given the supply voltage, the LED's forward voltage, and the target
-- current in mA, computes the series resistor needed, the nearest E12
-- standard value at or above it, the power it dissipates, and the actual
-- current you'll get with that standard resistor.
--
--   OK   : run another calculation
--   BACK : exit
--
-- In-memory only.

local lcd   = require("uni.lcd")
local nav   = require("uni.nav")
local input = require("uni.input")

local W, H = lcd.w(), lcd.h()

local C_BG     = lcd.color( 10,  12,  28)
local C_HUD_BG = lcd.color( 22,  22,  38)
local C_TEXT   = lcd.color(220, 220, 240)
local C_DIM    = lcd.color(140, 140, 180)
local C_VAL    = lcd.color(120, 220, 255)
local C_STD    = lcd.color(255, 200,  60)
local C_BAD    = lcd.color(255, 110, 110)

local HUD_H = 12
local E12 = { 1.0, 1.2, 1.5, 1.8, 2.2, 2.7, 3.3, 3.9, 4.7, 5.6, 6.8, 8.2 }

local function promptNumber(label, default)
  while true do
    local s = input.text(label, default or "0")
    if s == nil then return nil end
    local n = tonumber(s)
    if n then return n end
    default = s
  end
end

-- smallest E12 value (across decades) that is >= r
local function nearestStdGE(r)
  if r <= 0 then return nil end
  for exp = -1, 7 do
    local decade = 10 ^ exp
    for i = 1, #E12 do
      local v = E12[i] * decade
      if v >= r - 1e-9 then return v end
    end
  end
  return nil
end

local function fmtOhms(r)
  if r == nil then return "ERR" end
  local suffix, div
  if     r >= 1e6 then suffix, div = "M", 1e6
  elseif r >= 1e3 then suffix, div = "k", 1e3
  else                 suffix, div = "",  1 end
  return string.format("%g%s ohm", r / div, suffix)
end

local function fmtPower(p)
  if p == nil then return "ERR" end
  if p < 1 then return string.format("%g mW", p * 1000) end
  return string.format("%g W", p)
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "LED Resistor")
end

local function line(y, label, value, color)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(8, y, label)
  lcd.textColor(color, C_BG)
  lcd.print(8, y + 10, value)
end

local function drawResult(vs, vf, ma, ok, rreq, rstd, pstd, iact)
  lcd.rect(0, HUD_H + 1, W, H - HUD_H - 13, C_BG)
  if not ok then
    lcd.textSize(2)
    lcd.textColor(C_BAD, C_BG)
    lcd.print(8, HUD_H + 20, "Vs must be")
    lcd.print(8, HUD_H + 40, "> Vf, I > 0")
    lcd.textSize(1)
    lcd.textColor(C_DIM, C_BG)
    lcd.print(8, HUD_H + 66, string.format("Vs=%g Vf=%g I=%g mA", vs, vf, ma))
    return
  end
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_BG)
  lcd.print(8, HUD_H + 6, string.format("Vs %g  Vf %g  I %g mA", vs, vf, ma))
  local y = HUD_H + 22
  line(y,      "Resistor needed",      fmtOhms(rreq),                C_VAL)
  line(y + 24, "Nearest E12 (>=)",     fmtOhms(rstd),                C_STD)
  line(y + 48, "Power in resistor",    fmtPower(pstd),               C_VAL)
  line(y + 72, "Actual current",       string.format("%.2f mA", iact), C_VAL)
end

local function drawHint(text)
  lcd.rect(0, H - 12, W, 12, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(math.floor((W - lcd.textWidth(text)) / 2), H - 12, text)
end

-- ── Main loop ─────────────────────────────────────────────
while true do
  local vs = promptNumber("Supply voltage (V)", "5")
  if vs == nil then break end
  local vf = promptNumber("LED forward V (Vf)", "2")
  if vf == nil then break end
  local ma = promptNumber("LED current (mA)", "20")
  if ma == nil then break end

  local ok = (vs > vf) and (ma > 0)
  local rreq, rstd, pstd, iact
  if ok then
    local i = ma / 1000
    rreq = (vs - vf) / i
    rstd = nearestStdGE(rreq)
    iact = (vs - vf) / rstd * 1000          -- mA with the standard resistor
    pstd = (vs - vf) * (vs - vf) / rstd      -- power dissipated in resistor
  end

  lcd.fillScreen(C_BG)
  drawHUD()
  drawResult(vs, vf, ma, ok, rreq, rstd, pstd, iact)
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
