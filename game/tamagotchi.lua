--[[
@title Tamagotchi
@description Virtual pet that grows hungry and bored over time — feed it and play to keep it alive. Ported from hxd57's Bruce app.
@category Game
@author lshaf
]]
-- tamagotchi.lua — virtual pet, ported from hxd57's Tamagotchi (V2) for the
-- Bruce launcher. Pet decays over time: hunger climbs, happiness and
-- cleanliness drop. Feed / pet / clean to keep stats up. State persists to
-- /unigeek/games/tamagotchi.txt as JSON across power cycles (uses the RTC
-- epoch, so decay only accumulates if the device clock has been synced).
--
--   OK / UP / DOWN : open action menu (Pet / Feed / Clean / Heart / Settings /
--                    New Pet / Exit). The default UniGeek board only has
--                    four nav inputs, so any non-back press opens the menu —
--                    that mirrors the original "any key brings up choices".
--   BACK           : save and exit.
--
-- All in-loop drawing uses overdraw + textColor(fg, bg). Helpers are
-- pre-allocated above the while loop so no closures churn per frame.

local lcd    = require("uni.lcd")
local nav    = require("uni.nav")
local sd     = require("uni.sd")
local json   = require("uni.json")
local dialog = require("uni.dialog")
local input  = require("uni.input")
local time   = require("uni.time")

local W, H = lcd.w(), lcd.h()

-- ── Palettes ──────────────────────────────────────────────
local BG_PALETTE = {
  { name = "Peach",    color = lcd.color(255, 223, 186) },
  { name = "Mint",     color = lcd.color(186, 255, 201) },
  { name = "Pink",     color = lcd.color(255, 186, 255) },
  { name = "Blue",     color = lcd.color(186, 225, 255) },
  { name = "Yellow",   color = lcd.color(255, 255, 186) },
  { name = "White",    color = lcd.color(255, 255, 255) },
  { name = "Lavender", color = lcd.color(230, 230, 250) },
  { name = "Coral",    color = lcd.color(255, 127,  80) },
  { name = "Aqua",     color = lcd.color(127, 255, 212) },
  { name = "Beige",    color = lcd.color(245, 245, 220) },
}

local FACE_PALETTE = {
  { name = "Black",  color = lcd.color(  0,   0,   0) },
  { name = "White",  color = lcd.color(255, 255, 255) },
  { name = "Red",    color = lcd.color(255,   0,   0) },
  { name = "Blue",   color = lcd.color(  0,   0, 255) },
  { name = "Green",  color = lcd.color(  0, 255,   0) },
  { name = "Purple", color = lcd.color(128,   0, 128) },
}

local RED = lcd.color(255, 0, 0)

-- stateIndex 1 = stressed, 2 = neutral, 3 = happy
local FACES = {
  cat  = { " >_< ", "=^_^=", " ^-^ " },
  dog  = { " T_T ", " o_o ", " ^_^ " },
  bird = { " x_x ", " -_- ", " ^v^ " },
}

local SAVE_PATH = "/unigeek/games/tamagotchi.txt"

-- ── State (declared once) ─────────────────────────────────
local pet
local bg_color   = BG_PALETTE[1].color    -- "Peach"
local face_color = FACE_PALETTE[1].color  -- "Black"

local FACE_SIZE    = 2
local FACE_GLYPH_H = 16  -- default font cell × scale 2

local face_prev_x, face_prev_y, face_prev_w = -1, -1, 0

-- ── Helpers ───────────────────────────────────────────────
local function paletteLookup(palette, name)
  for _, e in ipairs(palette) do
    if e.name == name then return e.color end
  end
  return palette[1].color
end

local function paletteNames(palette)
  local out = {}
  for i, e in ipairs(palette) do out[i] = e.name end
  return out
end

local function nowSec()
  local t = time.now()
  return (t and t.epoch) or 0
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function newPet(name, ptype, hunger, cleanliness, happiness, tFed, tPet, tCleaned)
  if not (ptype and FACES[ptype]) then ptype = "cat" end
  local t = nowSec()
  return {
    name            = name or "gotchi",
    type            = ptype,
    hunger          = clamp(tonumber(hunger)      or 0,   0, 100),
    cleanliness     = clamp(tonumber(cleanliness) or 100, 0, 100),
    happiness       = clamp(tonumber(happiness)   or 50,  0, 100),
    timeLastFed     = tonumber(tFed)     or t,
    timeLastPet     = tonumber(tPet)     or t,
    timeLastCleaned = tonumber(tCleaned) or t,
  }
end

local function savePet()
  if not sd.exists("/unigeek/games") then sd.mkdir("/unigeek/games") end
  sd.write(SAVE_PATH, json.encode(pet))
end

local function loadPet()
  if not sd.exists(SAVE_PATH) then return nil end
  local raw = sd.read(SAVE_PATH) or ""
  if #raw == 0 then return nil end
  local data = json.decode(raw)
  if not data or type(data) ~= "table" then return nil end
  return newPet(data.name, data.type, data.hunger, data.cleanliness,
                data.happiness, data.timeLastFed, data.timeLastPet,
                data.timeLastCleaned)
end

-- Original JS used ms; we use seconds. 2 h between hunger ticks, 1 h
-- between happiness ticks, cleanliness drains 5%/h continuously.
local function updateHunger()
  local elapsed = nowSec() - pet.timeLastFed
  pet.hunger = clamp(pet.hunger + math.floor(elapsed / 7200) * 10, 0, 100)
end

local function updateHappiness()
  local elapsed = nowSec() - pet.timeLastPet
  pet.happiness = clamp(pet.happiness - math.floor(elapsed / 3600) * 5, 0, 100)
end

local function updateCleanliness()
  local elapsed = nowSec() - pet.timeLastCleaned
  pet.cleanliness = math.max(0, 100 - math.floor((elapsed / 3600) * 5))
end

local function feedPet()
  pet.hunger      = math.max(0, pet.hunger - 10)
  pet.happiness   = math.min(100, pet.happiness + 20)
  pet.timeLastFed = nowSec()
end

local function cleanPet()
  pet.cleanliness     = 100
  pet.timeLastCleaned = nowSec()
end

local function petPet()
  pet.happiness   = math.min(100, pet.happiness + 10)
  pet.timeLastPet = nowSec()
end

local function stateIndex()
  if pet.hunger >= 70 or pet.happiness <= 30 or pet.cleanliness <= 30 then
    return 1
  elseif pet.hunger >= 30 or pet.happiness <= 50 or pet.cleanliness <= 50 then
    return 2
  else
    return 3
  end
end

-- ── Layout / drawing ──────────────────────────────────────
local LINE_SPACING = 14
local STATUS_TOP   = H - 60
local FED_LINE_Y   = H - 30
local FACE_BASE_Y  = math.floor(H * 0.3)
local HAPPY_Y      = 10
local WIGGLE       = math.floor(W * 0.1)

local function drawSceneBackground()
  lcd.fillScreen(bg_color)
  face_prev_x = -1
end

local function eraseFace()
  if face_prev_x < 0 then return end
  -- +2 covers the 1-px bold overdraw on the right edge.
  lcd.rect(face_prev_x, face_prev_y, face_prev_w + 2, FACE_GLYPH_H, bg_color)
end

local function drawFace(face, x, y)
  lcd.textSize(FACE_SIZE)
  lcd.textColor(face_color, bg_color)
  lcd.print(x,     y, face)
  lcd.print(x + 1, y, face)   -- poor-man's bold
  face_prev_x = x
  face_prev_y = y
  face_prev_w = lcd.textWidth(face)
end

local function drawHappyLine()
  local txt = string.format("Happy: %3d%%", pet.happiness)
  lcd.textSize(FACE_SIZE)
  lcd.textColor(face_color, bg_color)
  local tw = lcd.textWidth(txt)
  lcd.print(math.floor((W - tw) / 2), HAPPY_Y, txt)
end

local function drawStatus()
  lcd.textSize(1)
  lcd.textColor(face_color, bg_color)
  lcd.print(10, STATUS_TOP,                string.format("Hngr:  %3d%%", pet.hunger))
  lcd.print(10, STATUS_TOP + LINE_SPACING, string.format("Clean: %3d%%", pet.cleanliness))

  local t = nowSec()
  local fedHrs = math.max(0, math.floor((t - pet.timeLastFed) / 3600))
  local petHrs = math.max(0, math.floor((t - pet.timeLastPet) / 3600))
  lcd.print(10, FED_LINE_Y, string.format("Fed:%4dh  Pet:%4dh", fedHrs, petHrs))
end

local function drawPet()
  local idx  = stateIndex()
  local face = FACES[pet.type][idx]
  local t    = uni.millis()

  -- Brief blink: replace non-space glyphs with a dash for 200 ms out of every 4 s.
  if t % 4000 < 200 then
    face = (face:gsub("[^%s]", "-"))
  end

  lcd.textSize(FACE_SIZE)
  local faceW = lcd.textWidth(face)
  local faceX = math.floor((W - faceW) / 2)

  if idx == 3 and (t % 1000) < 500 then
    faceX = faceX + math.floor(math.sin(t / 200) * WIGGLE)
  end

  eraseFace()
  drawFace(face, faceX, FACE_BASE_Y)
  drawHappyLine()
  drawStatus()
end

local function showHeartAnimation()
  local heart_small = "<3"
  local heart_pair  = "<3 <3"

  lcd.fillScreen(bg_color)
  lcd.textSize(2)
  lcd.textColor(face_color, bg_color)
  local tw = lcd.textWidth(heart_small)
  lcd.print(math.floor((W - tw) / 2), math.floor(H * 0.45), heart_small)
  uni.delay(700)

  lcd.fillScreen(bg_color)
  tw = lcd.textWidth(heart_pair)
  lcd.print(math.floor((W - tw) / 2), math.floor(H * 0.45), heart_pair)
  uni.delay(700)

  lcd.fillScreen(bg_color)
  lcd.textSize(3)
  lcd.textColor(RED, bg_color)
  tw = lcd.textWidth(heart_small)
  lcd.print(math.floor((W - tw) / 2), math.floor(H * 0.40), heart_small)
  uni.delay(1000)
end

-- ── New-pet creation ─────────────────────────────────────
local function createNewPet()
  local name = input.text("Pet's name?", "gotchi")
  if not name or #name == 0 then name = "gotchi" end
  local ptype = dialog.select("Pet type?", { "Cat", "Dog", "Bird" })
  if not ptype then ptype = "Cat" end
  pet = newPet(name, ptype:lower())
  savePet()
end

-- ── Menus ────────────────────────────────────────────────
local MENU_OPTIONS = { "Pet", "Feed", "Clean", "Heart", "Settings", "New Pet", "Exit" }

local function settingsMenu()
  local s = dialog.select("Settings", { "Background", "Face Color" })
  if s == "Background" then
    local c = dialog.select("Background", paletteNames(BG_PALETTE))
    if c then bg_color = paletteLookup(BG_PALETTE, c) end
  elseif s == "Face Color" then
    local c = dialog.select("Face Color", paletteNames(FACE_PALETTE))
    if c then face_color = paletteLookup(FACE_PALETTE, c) end
  end
end

-- Returns true when the user chose Exit.
local function handleMenu()
  local choice = dialog.select("Menu", MENU_OPTIONS)
  if not choice         then return false end
  if choice == "Exit"   then return true  end
  if choice == "Pet"       then petPet()
  elseif choice == "Feed"  then feedPet()
  elseif choice == "Clean" then cleanPet()
  elseif choice == "Heart" then showHeartAnimation()
  elseif choice == "Settings" then settingsMenu()
  elseif choice == "New Pet"  then
    if dialog.confirm("Delete current pet?") then
      sd.remove(SAVE_PATH)
      createNewPet()
    end
  end
  savePet()
  return false
end

-- ── Init ─────────────────────────────────────────────────
pet = loadPet()
if not pet then createNewPet() end

drawSceneBackground()

-- ── Main loop ────────────────────────────────────────────
while true do
  local btn = nav.btn()
  if btn == "back" then
    savePet()
    break
  end

  if btn == "ok" or btn == "up" or btn == "down" then
    if handleMenu() then
      savePet()
      break
    end
    drawSceneBackground()
  end

  updateHunger()
  updateHappiness()
  updateCleanliness()
  drawPet()

  uni.delay(50)
end
