-- bitwise.lua — 16-bit bitwise playground
-- Pick an operation, enter operand A (and B where it applies), and see A, B
-- and the result side by side in decimal, hex and 16-bit binary (grouped in
-- nibbles). Lua 5.1 has no bitwise operators, so every op is done by hand on
-- the bits — all values are treated as unsigned 16-bit (0..65535).
--
--   OK   : run another operation
--   BACK : exit
--
-- In-memory only.

local lcd    = require("uni.lcd")
local nav    = require("uni.nav")
local input  = require("uni.input")
local dialog = require("uni.dialog")

local W, H = lcd.w(), lcd.h()

local C_BG     = lcd.color( 10,  12,  28)
local C_HUD_BG = lcd.color( 22,  22,  38)
local C_TEXT   = lcd.color(220, 220, 240)
local C_DIM    = lcd.color(140, 140, 180)
local C_A      = lcd.color(120, 220, 255)
local C_B      = lcd.color(180, 200, 120)
local C_RES    = lcd.color(255, 200,  60)

local HUD_H = 12
local MASK  = 65535
local OPS   = { "AND", "OR", "XOR", "NOT A", "A SHL B", "A SHR B" }

-- ── Bit operations (manual, 16-bit) ──────────────────────
local function band(a, b)
  local r, p = 0, 1
  for _ = 0, 15 do
    if (a % 2 == 1) and (b % 2 == 1) then r = r + p end
    a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
  end
  return r
end

local function bor(a, b)
  local r, p = 0, 1
  for _ = 0, 15 do
    if (a % 2 == 1) or (b % 2 == 1) then r = r + p end
    a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
  end
  return r
end

local function bxor(a, b)
  local r, p = 0, 1
  for _ = 0, 15 do
    if (a % 2) ~= (b % 2) then r = r + p end
    a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
  end
  return r
end

local function apply(op, a, b)
  if op == "AND"     then return band(a, b) end
  if op == "OR"      then return bor(a, b) end
  if op == "XOR"     then return bxor(a, b) end
  if op == "NOT A"   then return MASK - a end
  local sh = math.min(b, 16)
  if op == "A SHL B" then return math.floor(a * (2 ^ sh)) % 65536 end
  if op == "A SHR B" then return math.floor(a / (2 ^ sh)) end
  return 0
end

-- ── Formatting ────────────────────────────────────────────
local function bin16(n)
  local s = ""
  for i = 15, 0, -1 do
    s = s .. tostring(math.floor(n / (2 ^ i)) % 2)
    if i % 4 == 0 and i > 0 then s = s .. " " end
  end
  return s
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Bitwise")
end

local function block(y, tag, n, color)
  lcd.textSize(1)
  lcd.textColor(color, C_BG)
  lcd.print(2, y, string.format("%-3s %5d  0x%04X", tag, n, n))
  lcd.print(2, y + 10, bin16(n))
end

local function drawResult(op, a, b, res, uses_b)
  lcd.rect(0, HUD_H + 1, W, H - HUD_H - 13, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(2, HUD_H + 4, "OP: " .. op)
  local y = HUD_H + 18
  block(y, "A", a, C_A)
  if uses_b then
    block(y + 24, "B", b, C_B)
    block(y + 48, "=", res, C_RES)
  else
    block(y + 24, "=", res, C_RES)
  end
end

local function drawHint(text)
  lcd.rect(0, H - 12, W, 12, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(math.floor((W - lcd.textWidth(text)) / 2), H - 12, text)
end

-- ── Main loop ─────────────────────────────────────────────
while true do
  local op = dialog.select("Operation", OPS)
  if op == nil then break end

  local a = input.number("A (0..65535)", 0, MASK, 0)
  if a == nil then break end

  local uses_b = (op ~= "NOT A")
  local b = 0
  if uses_b then
    local prompt = (op == "A SHL B" or op == "A SHR B")
                   and "B = shift amount (0..16)" or "B (0..65535)"
    b = input.number(prompt, 0, MASK, 0)
    if b == nil then break end
  end

  local res = apply(op, a, b)

  lcd.fillScreen(C_BG)
  drawHUD()
  drawResult(op, a, b, res, uses_b)
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
