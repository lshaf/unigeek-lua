-- resistor.lua — 4-band resistor color-code calculator
-- Dial in the colour of each band and read off the resistance and tolerance.
-- Two significant-digit bands, a multiplier band, and a tolerance band are
-- drawn on a resistor body; the active band is marked with an arrow.
--
--   OK   : select the next band (digit1 -> digit2 -> mult -> tol -> ...)
--   UP   : previous colour for the active band
--   DOWN : next colour for the active band
--   BACK : exit
--
-- In-memory only.

local lcd = require("uni.lcd")
local nav = require("uni.nav")

local W, H = lcd.w(), lcd.h()

local C_BG     = lcd.color( 10,  12,  28)
local C_HUD_BG = lcd.color( 22,  22,  38)
local C_TEXT   = lcd.color(220, 220, 240)
local C_DIM    = lcd.color(140, 140, 180)
local C_VAL    = lcd.color(255, 200,  60)
local C_BODY   = lcd.color(222, 196, 140)   -- resistor body (beige)
local C_LEAD   = lcd.color(170, 170, 185)   -- wire leads
local C_MARK   = lcd.color(255, 255, 255)

-- band colours
local K_BLACK  = lcd.color( 25,  25,  30)
local K_BROWN  = lcd.color(120,  72,  40)
local K_RED    = lcd.color(220,  45,  45)
local K_ORANGE = lcd.color(240, 140,  30)
local K_YELLOW = lcd.color(235, 215,  60)
local K_GREEN  = lcd.color( 45, 180,  85)
local K_BLUE   = lcd.color( 55,  95, 230)
local K_VIOLET = lcd.color(165,  85, 220)
local K_GREY   = lcd.color(140, 140, 150)
local K_WHITE  = lcd.color(240, 240, 245)
local K_GOLD   = lcd.color(205, 165,  70)
local K_SILVER = lcd.color(195, 195, 205)

local HUD_H = 12

-- Per-band option lists: { name, colour, value }
local DIGITS = {
  { "black", K_BLACK, 0 }, { "brown", K_BROWN, 1 }, { "red", K_RED, 2 },
  { "orange", K_ORANGE, 3 }, { "yellow", K_YELLOW, 4 }, { "green", K_GREEN, 5 },
  { "blue", K_BLUE, 6 }, { "violet", K_VIOLET, 7 }, { "grey", K_GREY, 8 },
  { "white", K_WHITE, 9 },
}
local MULTS = {
  { "black", K_BLACK, 1 }, { "brown", K_BROWN, 10 }, { "red", K_RED, 100 },
  { "orange", K_ORANGE, 1e3 }, { "yellow", K_YELLOW, 1e4 }, { "green", K_GREEN, 1e5 },
  { "blue", K_BLUE, 1e6 }, { "violet", K_VIOLET, 1e7 }, { "grey", K_GREY, 1e8 },
  { "white", K_WHITE, 1e9 }, { "gold", K_GOLD, 0.1 }, { "silver", K_SILVER, 0.01 },
}
local TOLS = {
  { "brown", K_BROWN, "1%" }, { "red", K_RED, "2%" }, { "green", K_GREEN, "0.5%" },
  { "blue", K_BLUE, "0.25%" }, { "violet", K_VIOLET, "0.1%" }, { "grey", K_GREY, "0.05%" },
  { "gold", K_GOLD, "5%" }, { "silver", K_SILVER, "10%" },
}
local BANDS = { DIGITS, DIGITS, MULTS, TOLS }

-- ── State ─────────────────────────────────────────────────
local sel    = { 5, 8, 3, 7 }   -- yellow, violet, red, gold => 47 x100 +-5%
local active = 1

-- ── Layout ────────────────────────────────────────────────
local BODY_W = math.min(160, math.floor(W * 0.7))
local BODY_H = math.max(28, math.floor(H * 0.18))
local BODY_X = math.floor((W - BODY_W) / 2)
local BODY_Y = HUD_H + 18
local BAND_W = math.max(6, math.floor(BODY_W * 0.09))
-- x of each band: three grouped on the left, tolerance set off to the right
local BAND_X = {
  BODY_X + math.floor(BODY_W * 0.12),
  BODY_X + math.floor(BODY_W * 0.28),
  BODY_X + math.floor(BODY_W * 0.44),
  BODY_X + math.floor(BODY_W * 0.78),
}

local function fmtOhms(r)
  local suffix, div
  if     r >= 1e9 then suffix, div = "G", 1e9
  elseif r >= 1e6 then suffix, div = "M", 1e6
  elseif r >= 1e3 then suffix, div = "k", 1e3
  elseif r >= 1   then suffix, div = "",  1
  else                 suffix, div = "m", 1e-3 end
  return string.format("%g%s ohm", r / div, suffix)
end

local function value()
  local d1 = DIGITS[sel[1]][3]
  local d2 = DIGITS[sel[2]][3]
  local m  = MULTS[sel[3]][3]
  return (d1 * 10 + d2) * m
end

-- ── Rendering ─────────────────────────────────────────────
local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Resistor")
end

local function drawResistor()
  -- clear the resistor area (body + arrow row above)
  lcd.rect(0, BODY_Y - 12, W, BODY_H + 16, C_BG)
  -- leads
  lcd.rect(BODY_X - 18, BODY_Y + math.floor(BODY_H / 2) - 1, BODY_W + 36, 2, C_LEAD)
  -- body
  lcd.fillRoundRect(BODY_X, BODY_Y, BODY_W, BODY_H, 5, C_BODY)
  -- bands
  for i = 1, 4 do
    local opt = BANDS[i][sel[i]]
    lcd.rect(BAND_X[i], BODY_Y, BAND_W, BODY_H, opt[2])
    if i == active then
      -- arrow above the active band
      local ax = BAND_X[i] + math.floor(BAND_W / 2)
      lcd.rect(ax - 1, BODY_Y - 8, 2, 6, C_MARK)
      lcd.rect(ax - 3, BODY_Y - 4, 6, 2, C_MARK)
    end
  end
end

local function drawInfo()
  local y = BODY_Y + BODY_H + 8
  lcd.rect(0, y, W, H - y - 12, C_BG)
  -- big value
  lcd.textSize(2)
  lcd.textColor(C_VAL, C_BG)
  local v = fmtOhms(value())
  lcd.print(math.floor((W - lcd.textWidth(v)) / 2), y, v)
  -- tolerance + active band colour
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  local tol = "Tolerance " .. TOLS[sel[4]][3]
  lcd.print(math.floor((W - lcd.textWidth(tol)) / 2), y + 20, tol)
  local names = { "digit 1", "digit 2", "multiplier", "tolerance" }
  local cur = string.format("%s: %s", names[active], BANDS[active][sel[active]][1])
  lcd.textColor(C_TEXT, C_BG)
  lcd.print(math.floor((W - lcd.textWidth(cur)) / 2), y + 32, cur)
end

local function drawHint()
  local text = "OK band   UP/DOWN colour   BACK exit"
  lcd.rect(0, H - 12, W, 12, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  if lcd.textWidth(text) > W then text = "OK band  UP/DN colour" end
  lcd.print(math.floor((W - lcd.textWidth(text)) / 2), H - 12, text)
end

-- ── Init ──────────────────────────────────────────────────
lcd.fillScreen(C_BG)
drawHUD()
drawResistor()
drawInfo()
drawHint()

-- ── Main loop ─────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then break end

  if btn == "ok" then
    active = (active % 4) + 1
    drawResistor()
    drawInfo()
  elseif btn == "up" or btn == "down" then
    local n = #BANDS[active]
    local d = (btn == "down") and 1 or -1
    sel[active] = ((sel[active] - 1 + d) % n) + 1
    drawResistor()
    drawInfo()
    uni.beep(880, 10)
  end

  uni.delay(33)
end
