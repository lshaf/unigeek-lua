--[[
@title Ohm's Law
@description Solve for voltage, current, resistance, or power given any two of the four.
@category Utility
@author lshaf
]]
-- ohms-law.lua — Ohm's law / power calculator
-- Pick which two of voltage (V), current (I), resistance (R) and power (P)
-- you know; the other two are calculated from Ohm's law and P = V*I.
-- Values are entered as text so decimals work (e.g. 3.3, 0.02). Units are
-- volts / amps / ohms / watts — convert mA to A yourself (20 mA = 0.02).
--
--   OK   : run another calculation
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
local C_KNOWN  = lcd.color(255, 200,  60)
local C_CALC   = lcd.color(120, 220, 255)
local C_BAD    = lcd.color(255, 110, 110)

local HUD_H = 12

-- which two quantities the user supplies
local PAIRS = { "V & I", "V & R", "I & R", "V & P", "I & P", "R & P" }

local function promptNumber(label, default)
  while true do
    local s = input.text(label, default or "0")
    if s == nil then return nil end          -- cancelled -> caller exits
    local n = tonumber(s)
    if n then return n end
    default = s                              -- bad input: re-ask, keep text
  end
end

local function fmt(n)
  if n == nil then return "ERR" end
  if n ~= n or n == math.huge or n == -math.huge then return "ERR" end
  if n == math.floor(n) then return tostring(math.floor(n)) end
  return string.format("%.4g", n)
end

-- Returns V, I, R, P (any may be nil on a divide-by-zero / invalid input).
local function solve(pair, a, b)
  local V, I, R, P
  if pair == "V & I" then
    V, I = a, b
    if I ~= 0 then R = V / I end
    P = V * I
  elseif pair == "V & R" then
    V, R = a, b
    if R ~= 0 then I = V / R; P = V * V / R end
  elseif pair == "I & R" then
    I, R = a, b
    V = I * R; P = I * I * R
  elseif pair == "V & P" then
    V, P = a, b
    if V ~= 0 then I = P / V; R = V * V / P end
    if P == 0 then R = nil end
  elseif pair == "I & P" then
    I, P = a, b
    if I ~= 0 then V = P / I; R = P / (I * I) end
  elseif pair == "R & P" then
    R, P = a, b
    if R >= 0 and P >= 0 then V = math.sqrt(P * R)
      if R ~= 0 then I = math.sqrt(P / R) end
    end
  end
  return V, I, R, P
end

local function knownSet(pair)
  return { V = pair:find("V") ~= nil, I = pair:find("I") ~= nil,
           R = pair:find("R") ~= nil, P = pair:find("P") ~= nil }
end

local function drawHUD()
  lcd.rect(0, 0, W, HUD_H, C_HUD_BG)
  lcd.rect(0, HUD_H, W, 1, C_DIM)
  lcd.textSize(1)
  lcd.textColor(C_TEXT, C_HUD_BG)
  lcd.print(2, 2, "Ohm's Law")
end

local function row(y, label, value, unit, known)
  lcd.textSize(2)
  lcd.textColor(known and C_KNOWN or (value == "ERR" and C_BAD or C_CALC), C_BG)
  lcd.print(8, y, string.format("%s = %s %s", label, value, unit))
  lcd.textSize(1)
end

local function drawResult(pair, V, I, R, P)
  lcd.rect(0, HUD_H + 1, W, H - HUD_H - 13, C_BG)
  local known = knownSet(pair)
  local y0 = HUD_H + 10
  row(y0,      "V", fmt(V), "V",   known.V)
  row(y0 + 22, "I", fmt(I), "A",   known.I)
  row(y0 + 44, "R", fmt(R), "ohm", known.R)
  row(y0 + 66, "P", fmt(P), "W",   known.P)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(8, y0 + 90, "yellow = entered")
end

local function drawHint(text)
  lcd.rect(0, H - 12, W, 12, C_BG)
  lcd.textSize(1)
  lcd.textColor(C_DIM, C_BG)
  lcd.print(math.floor((W - lcd.textWidth(text)) / 2), H - 12, text)
end

-- ── Main loop ─────────────────────────────────────────────
while true do
  local pair = dialog.select("Known values", PAIRS)
  if pair == nil then break end

  local first  = pair:sub(1, 1)
  local second = pair:sub(#pair, #pair)
  local labels = { V = "Voltage (V)", I = "Current (A)",
                   R = "Resistance (ohm)", P = "Power (W)" }
  local a = promptNumber(labels[first], "0")
  if a == nil then break end
  local b = promptNumber(labels[second], "0")
  if b == nil then break end

  local V, I, R, P = solve(pair, a, b)

  lcd.fillScreen(C_BG)
  drawHUD()
  drawResult(pair, V, I, R, P)
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
