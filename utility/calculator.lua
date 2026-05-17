-- calculator.lua — Calculator
-- Two-operand arithmetic with on-screen modal prompts. Picks operator
-- from + - * /. Divide-by-zero is flagged as ERR; the calc is kept in
-- the history regardless. History persists for the session only.
--
--   OK   : run another calculation
--   BACK : exit

local lcd    = require("uni.lcd")
local nav    = require("uni.nav")
local input  = require("uni.input")
local dialog = require("uni.dialog")

local W, H = lcd.w(), lcd.h()

-- ── Colours ───────────────────────────────────────────────
local C_BG       = lcd.color( 10,  12,  28)
local C_HUD_BG   = lcd.color( 22,  22,  38)
local C_TEXT     = lcd.color(220, 220, 240)
local C_DIM      = lcd.color(140, 140, 180)
local C_RESULT   = lcd.color(120, 220, 255)
local C_EQ_GOOD  = lcd.color(255, 220,  80)
local C_EQ_BAD   = lcd.color(255, 110, 110)
local C_HIST     = lcd.color(200, 200, 220)

local HUD_H      = 12
local MIN_OPERAND = -99999
local MAX_OPERAND =  99999
local MAX_HISTORY = 5
local OPERATORS  = { "+", "-", "*", "/" }

local history = {}

local function compute(a, op, b)
  if op == "+" then return a + b end
  if op == "-" then return a - b end
  if op == "*" then return a * b end
  if op == "/" then
    if b == 0 then return nil end
    return a / b
  end
end

local function fmtNum(n)
  if n == math.floor(n) then return tostring(math.floor(n)) end
  return string.format("%.4f", n)
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Calculator")
  if #history > 0 then
    local s = string.format("%d calc", #history)
    lcd.textColor(C_DIM, C_HUD_BG)
    local sw = lcd.textWidth(s)
    lcd.print(W - sw - 2, 2, s)
  end
end

local function drawExpression(a, op, b, result)
  local y = HUD_H + 16
  lcd.rect(0, y - 4, W, 24, C_BG)
  local expr, color
  if result == nil then
    expr  = string.format("%s %s %s = ERR", fmtNum(a), op, fmtNum(b))
    color = C_EQ_BAD
  else
    expr  = string.format("%s %s %s = %s", fmtNum(a), op, fmtNum(b), fmtNum(result))
    color = C_EQ_GOOD
  end
  lcd.textSize(2)
  lcd.textColor(color, C_BG)
  if lcd.textWidth(expr) > W - 4 then
    lcd.textSize(1)
  end
  local sw = lcd.textWidth(expr)
  lcd.print(math.floor((W - sw) / 2), y, expr)
  lcd.textSize(1)
end

local function drawHistory()
  local y = HUD_H + 50
  lcd.rect(0, y, W, H - y - 12, C_BG)
  if #history == 0 then return end
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(2, y, "PREVIOUS")
  for i = 1, math.min(#history - 1, MAX_HISTORY) do
    local entry = history[#history - i]
    lcd.textColor(C_HIST, C_BG)
    lcd.print(2, y + 12 + (i - 1) * 10, entry)
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
  local a = input.number("First number", MIN_OPERAND, MAX_OPERAND, 0)
  if a == nil then break end

  local op = dialog.select("Operator", OPERATORS)
  if op == nil then break end

  local b = input.number("Second number", MIN_OPERAND, MAX_OPERAND, 0)
  if b == nil then break end

  local result = compute(a, op, b)
  local entry
  if result == nil then
    entry = string.format("%s %s %s = ERR", fmtNum(a), op, fmtNum(b))
  else
    entry = string.format("%s %s %s = %s", fmtNum(a), op, fmtNum(b), fmtNum(result))
  end
  history[#history + 1] = entry
  if #history > MAX_HISTORY * 2 then table.remove(history, 1) end

  lcd.fillScreen(C_BG)
  drawHUD()
  drawExpression(a, op, b, result)
  drawHistory()
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
